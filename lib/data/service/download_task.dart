import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content.dart';
import 'download_service.dart';
import 'download_store.dart';
import 'native_bridge.dart';
import '../../core/auth/token_store.dart';
import 'resource_service.dart';
import 'stream_service.dart';

/// 任务状态（R1 下载任务化：视频支持 暂停/恢复/取消）。
enum DownloadStatus { queued, downloading, paused, done, failed, cancelled }

/// 任务类型。图片/小说**没有暂停/恢复**，只有取消。
enum DownloadType { video, image, fiction }

/// 任务执行体（注入空实现即可在测试里驱动状态机）。
typedef DownloadRunner = Future<void> Function(DownloadTask task);

/// 一次下载任务（内存态；完成/失败/取消后保留在列表里直到用户移除）。
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.title,
    required this.kind,
    required this.type,
    this.quality,
    this.coverPath,
    this.mediaPath,
    this.pages,
    this.scheme,
    this.chapters,
    this.suffix = '',
    this.toMp4 = true,
  });

  /// 唯一 ID：`kind_id[_quality]`，与 [DownloadRecord.id] 一致。
  final String id;
  final String title;
  final ContentKind kind;
  final DownloadType type;
  final String? quality;
  final String? coverPath;

  /// video 专用：详情页 `media[quality]`。
  final String? mediaPath;

  /// image 专用：页表。
  final List<ReadPage>? pages;
  final ImageScheme? scheme;

  /// fiction 专用：章表。
  final List<ResourceRef>? chapters;

  /// fiction 专用：范围后缀（如 `第3章`/`选5章`）。空表示整本；
  /// 用于区分「下载本章 / 选集」与「全本」的任务 id 与输出文件名，避免互相覆盖。
  final String suffix;

  final bool toMp4;

  DownloadStatus status = DownloadStatus.queued;

  /// 已完成单元 / 总单元（分片·页·章）。
  int done = 0;
  int total = 0;

  /// 已解密落盘字节数。
  int bytes = 0;

  /// 速度（字节/秒）。
  double speed = 0;

  /// UI 标签（分片 12/304、转 MP4…、已暂停…）。
  String label = '排队中';

  String? error;
  String? outputPath;

  // ---- 下载链接（可在「下载」页复制/分享） ----
  /// 加密链接：视频=m3u8 地址；图片=首个加密图；小说=首个正文地址。
  String? encryptedUrl;

  /// 解密密钥链接：视频=key.php（AES-128 密钥）；图片/小说通常无独立密钥链接。
  String? keyUrl;

  /// 解密后链接：成品本地文件路径（视频 mp4/ts、图片 zip、小说 txt）。
  String? decryptedUrl;

  // ---- 控制位（仅 DownloadManager 写） ----
  bool pauseRequested = false;
  bool cancelRequested = false;
  bool running = false;
  CancelToken? cancelToken;

  bool get isTerminal =>
      status == DownloadStatus.done ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  bool get isActive => !isTerminal;

  /// 仅视频支持暂停（用户确认：图片没有暂停/恢复按钮）。
  bool get canPause => type == DownloadType.video && !isTerminal;

  bool get canResume => status == DownloadStatus.paused;

  bool get canCancel => !isTerminal;

  bool get canRetry =>
      status == DownloadStatus.failed || status == DownloadStatus.cancelled;
}

/// 下载管理器：任务队列 + 暂停/恢复/取消 + 并发数设置 + 完成记录落盘。
///
/// 视频走 [StreamService.downloadSegments]（分片落盘断点续传），
/// 图片/小说并行拉取（仅可取消）；完成/失败状态同步进 [DownloadStore]（R2 历史）。
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.streams,
    required this.resources,
    required this.store,
    required this.service,
    required this.prefs,
    this.tokenStore,
    DownloadRunner? runner,
  }) : _runner = runner {
    _checkExpired();
  }

  final StreamService streams;
  final ResourceService resources;
  final DownloadStore store;
  final DownloadService service;
  final SharedPreferences prefs;
  final DownloadRunner? _runner;

  static const String concurrencyKey = 'download_concurrency';

  /// 图片下载（漫画/图集）完成后是否额外导出单图到相册 `Pictures/mmlu`。
  /// 默认关闭：默认只产出 `Download/mmlu/<分类>/<id>.zip`，避免重复占空间。
  static const String exportGalleryKey = 'download_export_gallery';

  final List<DownloadTask> _tasks = <DownloadTask>[];

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.isActive).toList();
  List<DownloadTask> get finishedTasks =>
      _tasks.where((t) => t.isTerminal).toList();

  /// 多线程并发数（1/2/4/8，自由调整）。
  int get concurrency {
    final v = prefs.getInt(concurrencyKey) ?? 4;
    return v.clamp(1, 8);
  }

  set concurrency(int value) {
    prefs.setInt(concurrencyKey, value.clamp(1, 8));
    notifyListeners();
  }

  /// 图片下载后是否额外导出单图到相册（默认 false）。
  bool get exportToGallery => prefs.getBool(exportGalleryKey) ?? false;

  set exportToGallery(bool value) {
    prefs.setBool(exportGalleryKey, value);
    notifyListeners();
  }

  DownloadTask? byId(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// [id] 是否已有对应任务（下载页据此把任务区与历史区去重）。
  bool hasTask(String id) => byId(id) != null;

  /// 按需把「图集/漫画」全部页**下载→解密→打包**为本地 zip，返回 zip 文件路径。
  ///
  /// 与下载任务无关：不新建/登记任务、不发完成通知，仅产出
  /// `Download/mmlu/<分类>/<标题>.zip`；任一分页失败即抛 [StateError]。
  /// 解密后的图片先落临时目录再流式压包，**不在内存里堆积全部图片**。
  Future<String> packImages({
    required ContentKind kind,
    required String title,
    required String id,
    required List<ReadPage> pages,
    ImageScheme scheme = ImageScheme.perImage,
  }) async {
    if (pages.isEmpty) throw StateError('无图片');
    final root = await service.rootDir(tokenStore: tokenStore);
    final dir = await service.subDir(kind.label);
    final zipPath = p.join(dir.path, '${_safeName(title, id)}.zip');
    final tmp = Directory(p.join(root.path, '.imgs_pack_$id'))..createSync(recursive: true);
    try {
      final paths = await _fetchImagesToDir(
        kind: kind,
        pages: pages,
        scheme: scheme,
        dir: tmp,
      );
      await _zipFiles(paths, _imageNames(pages.length), zipPath);
      return zipPath;
    } finally {
      await _deleteDir(tmp.path);
    }
  }

  /// 新增视频下载任务。
  String addVideo({
    required ContentItem item,
    required String mediaPath,
    required String quality,
    bool toMp4 = true,
  }) {
    final id = '${item.kind.tag}_${item.id}_$quality';
    return _add(DownloadTask(
      id: id,
      title: item.title,
      kind: item.kind,
      type: DownloadType.video,
      quality: quality,
      coverPath: item.thumbPath,
      mediaPath: mediaPath,
      toMp4: toMp4,
    ));
  }

  /// 新增图片打包下载任务（漫画/图集；无暂停，仅取消）。
  ///
  /// [scope] 非空（漫画只选部分章节）时，任务 id 与 zip 文件名带上作用域，
  /// 避免与「全本打包」互相覆盖。
  String addImages({
    required ContentItem item,
    required List<ReadPage> pages,
    ImageScheme scheme = ImageScheme.perImage,
    String scope = '',
  }) {
    final id = scope.isEmpty
        ? '${item.kind.tag}_${item.id}'
        : '${item.kind.tag}_${item.id}_${_stableHash(scope)}';
    return _add(DownloadTask(
      id: id,
      title: item.title,
      kind: item.kind,
      type: DownloadType.image,
      coverPath: item.cover?.path,
      pages: List<ReadPage>.unmodifiable(pages),
      scheme: scheme,
      suffix: scope,
    ));
  }

  /// 新增小说下载任务（并行拉章、按序拼接；无暂停，仅取消）。
  ///
  /// [scope] 用于区分「全本」与「单章 / 选集」：非空时任务 id 与产物文件名都会带上
  /// 作用域（含章节集合的稳定哈希），避免同一本书的不同下载互相覆盖/去重。
  String addFiction({
    required ContentItem item,
    required List<ResourceRef> chapters,
    String scope = '',
  }) {
    final paths = chapters.map((c) => c.path).join('\u0001');
    final id = scope.isEmpty
        ? 'fiction_${item.id}'
        : 'fiction_${item.id}_${_stableHash('$scope|$paths')}';
    return _add(DownloadTask(
      id: id,
      title: item.title,
      kind: item.kind,
      type: DownloadType.fiction,
      coverPath: item.cover?.path,
      chapters: List<ResourceRef>.unmodifiable(chapters),
      suffix: scope,
    ));
  }

  /// 进程间稳定的短哈希（FNV-1a 32 位，十六进制）；仅用于任务/文件名去重。
  static String _stableHash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  String _add(DownloadTask task) {
    final existing = byId(task.id);
    if (existing != null) {
      if (existing.isActive) return task.id; // 已在下载 → 去重
      _tasks.remove(existing);
    }
    _tasks.insert(0, task);
    notifyListeners();
    _launch(task);
    return task.id;
  }

  void pause(DownloadTask t) {
    if (!t.canPause || t.status == DownloadStatus.paused) return;
    t.pauseRequested = true;
    if (!t.running) {
      t.status = DownloadStatus.paused;
      t.label = '已暂停';
      t.speed = 0;
    } else {
      t.label = '暂停中…';
    }
    notifyListeners();
  }

  void resume(DownloadTask t) {
    if (!t.canResume) return;
    t.pauseRequested = false;
    t.status = DownloadStatus.queued;
    t.label = '排队中';
    notifyListeners();
    _launch(t);
  }

  void cancel(DownloadTask t) {
    if (!t.canCancel) return;
    t.cancelRequested = true;
    t.cancelToken?.cancel('user cancelled');
    if (t.running) {
      t.label = '取消中…';
      notifyListeners();
    } else {
      unawaited(_finishCancelled(t));
    }
  }

  void retry(DownloadTask t) {
    if (!t.canRetry) return;
    t.cancelRequested = false;
    t.pauseRequested = false;
    t.error = null;
    t.status = DownloadStatus.queued;
    t.label = '排队中';
    notifyListeners();
    _launch(t);
  }

  /// 移除终态任务**记录**（保留本地已下载文件与相册导出）。
  ///
  /// 只清掉任务与 R2 历史记录，以及下载中途的临时分片目录 `.parts_<id>`；
  /// **不删** `Download/mmlu/<分类>/<标题>.*` 成品，也**不删** `Pictures/mmlu/<标题>`。
  /// （用户确认：删记录不应连带删文件；要清空间请自行到文件管理器删。）
  Future<void> remove(DownloadTask t) async {
    if (t.isActive) return;
    _tasks.remove(t);
    notifyListeners();
    await store.removeMany([t.id]);
    await _deleteDir(await _partDirOf(t.id));
  }

  /// 清空已结束任务（仅终态）。
  Future<void> clearFinished() async {
    final gone = finishedTasks;
    if (gone.isEmpty) return;
    _tasks.removeWhere((t) => t.isTerminal);
    notifyListeners();
    await store.removeMany(gone.map((t) => t.id));
    // 连带清理失败/中断任务的临时分片目录（成品文件仍保留）。
    for (final t in gone) {
      await _deleteDir(await _partDirOf(t.id));
    }
  }

  void _launch(DownloadTask t) => unawaited(_safeRun(t));

  Future<void> _safeRun(DownloadTask t) async {
    try {
      final runner = _runner;
      if (runner != null) {
        await runner(t);
      } else {
        await _execute(t);
      }
    } catch (e) {
      if (t.cancelRequested) {
        await _finishCancelled(t);
      } else if (t.pauseRequested) {
        t.status = DownloadStatus.paused;
        t.label = '已暂停';
        t.speed = 0;
        t.running = false;
        notifyListeners();
      } else {
        t.status = DownloadStatus.failed;
        t.error = e.toString();
        t.label = '失败';
        t.speed = 0;
        t.running = false;
        await _upsertRecord(t, status: 'failed');
        notifyListeners();
      }
    }
  }

  Future<void> _execute(DownloadTask t) async {
    if (t.cancelRequested) {
      await _finishCancelled(t);
      return;
    }
    t
      ..running = true
      ..status = DownloadStatus.downloading
      ..pauseRequested = false
      ..error = null
      ..label = '准备中…'
      ..speed = 0
      ..cancelToken = CancelToken();
    notifyListeners();
    try {
      switch (t.type) {
        case DownloadType.video:
          await _runVideo(t);
        case DownloadType.image:
          await _runImages(t);
        case DownloadType.fiction:
          await _runFiction(t);
      }
    } finally {
      t.running = false;
    }
  }

  // ---- 视频：分片断点续传 → 合并 → MP4 -----------------------------------

  Future<void> _runVideo(DownloadTask t) async {
    final mediaPath = t.mediaPath;
    if (mediaPath == null) throw StateError('缺少 mediaPath');
    final dir = await service.subDir(t.kind.label);
    final partDir = p.join((await service.rootDir(tokenStore: tokenStore)).path, '.parts_${t.id}');
    final m3u8Url = streams.buildM3u8Url(mediaPath);
    t.encryptedUrl = m3u8Url;
    await _upsertRecord(
      t,
      status: 'downloading',
      filePath: p.join(dir.path, '${_safeName(t.title, t.id)}.ts'),
      encryptedUrl: m3u8Url,
    );

    final info = StreamService.parseM3u8(await streams.fetchM3u8(mediaPath));
    t.keyUrl = info.keyUri;
    t.total = info.segments.length;
    notifyListeners();

    var lastBytes = 0;
    var lastAt = DateTime.now();
    final res = await streams.downloadSegments(
      info: info,
      partDir: partDir,
      concurrency: concurrency,
      cancelToken: t.cancelToken,
      shouldPause: () => t.pauseRequested,
      onProgress: (done, total, bytes) {
        t.done = done;
        t.total = total;
        t.bytes = bytes;
        final now = DateTime.now();
        final dt = now.difference(lastAt).inMilliseconds;
        if (dt >= 400) {
          final inst = (bytes - lastBytes) * 1000 / dt;
          t.speed = t.speed == 0 ? inst : t.speed * 0.6 + inst * 0.4;
          lastBytes = bytes;
          lastAt = now;
        }
        notifyListeners();
      },
    );

    if (t.cancelRequested) {
      await _finishCancelled(t, partDir: partDir);
      return;
    }
    if (!res.complete) {
      // worker 因暂停退出：分片已落盘，可跨会话续传。
      t
        ..status = DownloadStatus.paused
        ..label = '已暂停'
        ..speed = 0;
      notifyListeners();
      return;
    }

    t.label = '合并分片…';
    t.speed = 0;
    notifyListeners();
    final tsPath = p.join(dir.path, '${_safeName(t.title, t.id)}.ts');
    await _concatParts(partDir, tsPath);

    var outPath = tsPath;
    if (t.toMp4) {
      t.label = '转 MP4…';
      notifyListeners();
      final mp4Path = p.join(dir.path, '${_safeName(t.title, t.id)}.mp4');
      if (await service.converter.tsToMp4(tsPath, mp4Path)) {
        outPath = mp4Path;
        try {
          File(tsPath).deleteSync();
        } catch (_) {}
      }
    }
    await _deleteDir(partDir);

    t
      ..status = DownloadStatus.done
      ..outputPath = outPath
      ..decryptedUrl = outPath
      ..bytes = res.bytes
      ..label = '完成'
      ..speed = 0;
    await _upsertRecord(
      t,
      status: 'done',
      filePath: outPath,
      encryptedUrl: m3u8Url,
      keyUrl: info.keyUri,
      decryptedUrl: outPath,
      totalBytes: res.bytes,
    );
    // 视频成品进入系统媒体库（相册/视频）
    if (outPath.toLowerCase().endsWith('.mp4')) {
      unawaited(service.scanMedia(outPath));
    }
    _notifyDone(t);
    notifyListeners();
  }

  // ---- 图片：并行拉取 + 解密 → zip（仅取消，无暂停） -----------------------

  Future<void> _runImages(DownloadTask t) async {
    final pages = t.pages ?? const <ReadPage>[];
    if (pages.isEmpty) throw StateError('无图片');
    final root = await service.rootDir(tokenStore: tokenStore);
    final dir = await service.subDir(t.kind.label);
    final zipPath = p.join(dir.path,
        '${_safeName(t.title, t.id)}${t.suffix.isEmpty ? '' : '_${_safeName(t.suffix, '')}'}.zip');
    final firstUrl = pages.isEmpty
        ? null
        : resources.urlFor(t.kind, pages.first.path);
    t.encryptedUrl = firstUrl;
    t.keyUrl = pages.isEmpty ? null : pages.first.key;
    await _upsertRecord(
      t,
      status: 'downloading',
      filePath: zipPath,
      encryptedUrl: firstUrl,
      keyUrl: t.keyUrl,
    );

    final names = _imageNames(pages.length);
    final tmp = Directory(p.join(root.path, '.imgs_${t.id}'))
      ..createSync(recursive: true);
    try {
      final pending = <int>[for (var i = 0; i < pages.length; i++) i];
      var done = 0;
      var bytes = 0;
      t.total = pages.length;
      notifyListeners();

      Future<void> worker() async {
        while (pending.isNotEmpty) {
          if (t.cancelRequested) return;
          final i = pending.removeLast();
          final pg = pages[i];
          final ref = ResourceRef(
            path: pg.path,
            scheme: t.scheme ?? ImageScheme.perImage,
            key: pg.key,
            iv: pg.iv,
          );
          final b = await resources.fetchDecrypted(t.kind, ref);
          if (b.isEmpty) throw StateError('第 ${i + 1} 页为空');
          // 逐页落临时文件，避免把整本图片同时驻留内存。
          await File(p.join(tmp.path, names[i])).writeAsBytes(b, flush: true);
          done++;
          bytes += b.length;
          t.done = done;
          t.bytes = bytes;
          t.label = '$done/${pages.length}';
          notifyListeners();
        }
      }

      await Future.wait(
          List.generate(concurrency.clamp(1, 8), (_) => worker()));

      if (t.cancelRequested) {
        await _finishCancelled(t);
        return;
      }

      final files = <String>[
        for (var i = 0; i < pages.length; i++) p.join(tmp.path, names[i]),
      ];
      for (var i = 0; i < files.length; i++) {
        if (!File(files[i]).existsSync()) throw StateError('第 ${i + 1} 页下载失败');
      }
      await _zipFiles(files, names, zipPath);
      if (exportToGallery) {
        unawaited(_saveImagesToGallery(t, files));
      }

      t
        ..status = DownloadStatus.done
        ..outputPath = zipPath
        ..decryptedUrl = zipPath
        ..bytes = bytes
        ..label = '完成'
        ..speed = 0;
      await _upsertRecord(
        t,
        status: 'done',
        filePath: zipPath,
        encryptedUrl: firstUrl,
        keyUrl: t.keyUrl,
        decryptedUrl: zipPath,
        totalBytes: bytes,
      );
      _notifyDone(t);
      notifyListeners();
    } finally {
      await _deleteDir(tmp.path);
    }
  }

  /// 图片文件名（0001.jpg …，与 zip 内条目名一致，保证按序）。
  static List<String> _imageNames(int count) => [
        for (var i = 0; i < count; i++)
          '${(i + 1).toString().padLeft(4, '0')}.jpg',
      ];

  /// 并行下载并解密页表到 [dir]，返回按序的文件路径（缺页即抛）。
  Future<List<String>> _fetchImagesToDir({
    required ContentKind kind,
    required List<ReadPage> pages,
    required ImageScheme scheme,
    required Directory dir,
  }) async {
    final names = _imageNames(pages.length);
    final pending = <int>[for (var i = 0; i < pages.length; i++) i];
    Future<void> worker() async {
      while (pending.isNotEmpty) {
        final i = pending.removeLast();
        final pg = pages[i];
        final b = await resources.fetchDecrypted(
          kind,
          ResourceRef(path: pg.path, scheme: scheme, key: pg.key, iv: pg.iv),
        );
        if (b.isEmpty) throw StateError('第 ${i + 1} 页为空');
        await File(p.join(dir.path, names[i])).writeAsBytes(b, flush: true);
      }
    }

    await Future.wait(
        List.generate(concurrency.clamp(1, 8), (_) => worker()));
    final files = <String>[for (final n in names) p.join(dir.path, n)];
    for (var i = 0; i < files.length; i++) {
      if (!File(files[i]).existsSync()) throw StateError('第 ${i + 1} 页下载失败');
    }
    return files;
  }

  /// 把磁盘上的图片**流式**压成 zip（逐条写盘，内存只驻留单张图片）。
  static Future<void> _zipFiles(
      List<String> files, List<String> names, String zipPath) async {
    final enc = ZipFileEncoder();
    enc.create(zipPath, level: ZipFileEncoder.GZIP);
    try {
      for (var i = 0; i < files.length; i++) {
        await enc.addFile(File(files[i]), names[i]);
      }
    } finally {
      await enc.close();
    }
  }

  /// 把已解密的图片写入相册并通知系统媒体库（从临时文件读取，不再整本驻留内存）。
  Future<void> _saveImagesToGallery(
      DownloadTask t, List<String> files) async {
    try {
      final dir = await service.galleryDir(_safeName(t.title));
      if (dir == null) return;
      for (var i = 0; i < files.length; i++) {
        final src = File(files[i]);
        if (!src.existsSync()) continue;
        final f = File(
            p.join(dir.path, '${(i + 1).toString().padLeft(4, '0')}.jpg'));
        await f.writeAsBytes(await src.readAsBytes());
        await service.scanMedia(f.path);
      }
    } catch (_) {}
  }

  /// 文件名安全的标题（相册子目录名 / 下载文件名）。
  ///
  /// 下载产物一律以**作品名**命名（小说/动漫/漫画/图集），非法字符替换为 `_`，
  /// 超长截断；标题为空时回退 [fallback]（一般传任务 id）。
  static String _safeName(String s, [String fallback = 'mmlu']) {
    final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
    final limited = cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
    return limited.isEmpty ? fallback : limited;
  }

  /// 下载完成通知。
  void _notifyDone(DownloadTask t) {
    unawaited(NativeBridge.notify(
      id: t.id.hashCode & 0x7fffffff,
      title: '下载完成',
      body: t.title,
    ));
  }

  // ---- 小说：并行拉章（保序）→ txt（仅取消，无暂停） -----------------------

  Future<void> _runFiction(DownloadTask t) async {
    final chapters = t.chapters ?? const <ResourceRef>[];
    if (chapters.isEmpty) throw StateError('无章节');
    final dir = await service.subDir(t.kind.label);
    final outPath = p.join(
        dir.path, '${_safeName(t.title, t.id)}${t.suffix.isEmpty ? '' : '_${_safeName(t.suffix, '')}'}.txt');
    final firstUrl = chapters.isEmpty
        ? null
        : resources.urlFor(t.kind, chapters.first.path);
    t.encryptedUrl = firstUrl;
    await _upsertRecord(
      t,
      status: 'downloading',
      filePath: outPath,
      encryptedUrl: firstUrl,
    );

    final texts = List<String?>.filled(chapters.length, null);
    final pending = <int>[for (var i = 0; i < chapters.length; i++) i];
    var done = 0;
    t.total = chapters.length;
    notifyListeners();

    Future<void> worker() async {
      while (pending.isNotEmpty) {
        if (t.cancelRequested) return;
        final i = pending.removeLast();
        texts[i] = await resources.getText(t.kind, chapters[i].path);
        done++;
        t.done = done;
        t.bytes = 0;
        t.label = '$done/${chapters.length}';
        notifyListeners();
      }
    }

    await Future.wait(
        List.generate(concurrency.clamp(1, 8), (_) => worker()));

    if (t.cancelRequested) {
      await _finishCancelled(t);
      return;
    }

    final buf = StringBuffer();
    for (var i = 0; i < texts.length; i++) {
      final text = texts[i];
      if (text == null) throw StateError('第 ${i + 1} 章拉取失败');
      if (chapters.length > 1) buf.writeln('第 ${i + 1} 章\n');
      buf.writeln(text);
    }
    await File(outPath).writeAsString(buf.toString());
    // 用实际落盘字节数（UTF-8），别拿 StringBuffer.length（UTF-16 字符数）当大小。
    final outBytes = await File(outPath).length();

    t
      ..status = DownloadStatus.done
      ..outputPath = outPath
      ..decryptedUrl = outPath
      ..bytes = outBytes
      ..label = '完成'
      ..speed = 0;
    await _upsertRecord(
      t,
      status: 'done',
      filePath: outPath,
      encryptedUrl: t.encryptedUrl,
      decryptedUrl: outPath,
      totalBytes: outBytes,
    );
    _notifyDone(t);
    notifyListeners();
  }

  // ---- 收尾工具 ------------------------------------------------------------

  Future<String> _partDirOf(String id) async {
    final dir = await service.rootDir(tokenStore: tokenStore);
    return p.join(dir.path, '.parts_$id');
  }

  Future<void> _concatParts(String partDir, String outPath) async {
    final dir = Directory(partDir);
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final sink = File(outPath).openWrite();
    try {
      for (final f in files) {
        sink.add(await f.readAsBytes());
      }
    } finally {
      await sink.close();
    }
  }

  Future<void> _finishCancelled(DownloadTask t, {String? partDir}) async {
    t
      ..status = DownloadStatus.cancelled
      ..label = '已取消'
      ..speed = 0;
    await _deleteDir(partDir ?? await _partDirOf(t.id));
    await store.removeMany([t.id]);
    notifyListeners();
  }

  Future<void> _deleteDir(String path) async {
    try {
      final d = Directory(path);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  Future<void> _upsertRecord(
    DownloadTask t, {
    required String status,
    String? filePath,
    String? encryptedUrl,
    String? keyUrl,
    String? decryptedUrl,
    int totalBytes = 0,
  }) async {
    await store.upsert(DownloadRecord(
      id: t.id,
      title: t.title,
      kind: t.kind.tag,
      quality: t.quality,
      status: status,
      filePath: filePath ?? '',
      encryptedUrl: encryptedUrl,
      keyUrl: keyUrl,
      decryptedUrl: decryptedUrl,
      totalBytes: totalBytes,
      coverPath: t.coverPath,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }
}


  void _checkExpired() {
    Future.microtask(() async {
      try {
        final enable = await (tokenStore?.getAutoDelete12h() ?? Future.value(true));
        if (!enable) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        final all = store.load();
        final remove = <String>[];
        for (final r in all) {
          if (r.status == 'done' || r.status == 'failed' || r.status == 'cancelled') {
            final end = r.createdAt;
            if (end > 0 && now - end > 12 * 60 * 60 * 1000) {
              remove.add(r.id);
              try {
                if (r.filePath.isNotEmpty) {
                  final f = File(r.filePath);
                  if (f.existsSync()) f.deleteSync();
                }
              } catch (_) {}
            }
          }
        }
        if (remove.isNotEmpty) {
          await store.removeMany(remove);
        }
      } catch (_) {}
    });
  }

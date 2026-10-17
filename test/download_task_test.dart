import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/core/auth/token_store.dart';
import 'package:mmlu_client/core/domain/domain_store.dart';
import 'package:mmlu_client/data/models/content.dart';
import 'package:mmlu_client/data/service/download_service.dart';
import 'package:mmlu_client/data/service/download_store.dart';
import 'package:mmlu_client/data/service/download_task.dart';
import 'package:mmlu_client/data/service/resource_service.dart';
import 'package:mmlu_client/data/service/stream_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 任务状态机测试：注入 noop runner，只驱动 暂停/恢复/取消/重试/去重/并发。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late DownloadStore store;
  late DownloadManager mgr;

  ContentItem item({int id = 1, ContentKind kind = ContentKind.animat}) =>
      ContentItem(kind: kind, id: id, title: '标题$id', thumbPath: '/t/$id.jpg');

  DownloadManager makeManager({DownloadRunner? runner}) {
    final domains = DomainStore(prefs);
    return DownloadManager(
      streams: StreamService(domains: domains, tokenStore: TokenStore(prefs)),
      resources: ResourceService(domains),
      store: store,
      service: DownloadService(
        rootOverride: () async => Directory.systemTemp.createTempSync('mmlu_t_'),
      ),
      prefs: prefs,
      runner: runner ?? (t) async {},
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = DownloadStore(prefs);
    mgr = makeManager();
  });

  group('并发数（多线程自由调整）', () {
    test('默认 4；可设 1/2/4/8；越界 clamp 到 1..8', () {
      expect(mgr.concurrency, 4);
      for (final n in const [1, 2, 4, 8]) {
        mgr.concurrency = n;
        expect(mgr.concurrency, n);
      }
      mgr.concurrency = 0;
      expect(mgr.concurrency, 1);
      mgr.concurrency = 99;
      expect(mgr.concurrency, 8);
    });

    test('设置写入 SharedPreferences，重建实例后仍生效', () {
      mgr.concurrency = 8;
      final again = makeManager();
      expect(again.concurrency, 8);
    });
  });

  group('相册导出开关（漫画/图集）', () {
    test('默认关闭；可开启并持久化', () {
      expect(mgr.exportToGallery, isFalse);
      mgr.exportToGallery = true;
      expect(mgr.exportToGallery, isTrue);
      final again = makeManager();
      expect(again.exportToGallery, isTrue);
      again.exportToGallery = false;
      expect(again.exportToGallery, isFalse);
    });
  });

  group('入队与去重', () {
    test('addVideo 生成 kind_id_quality，活动任务不重复入队', () {
      final a = mgr.addVideo(
          item: item(), mediaPath: '/v3/x.m3u8', quality: '720');
      expect(a, 'animat_1_720');
      final b = mgr.addVideo(
          item: item(), mediaPath: '/v3/x.m3u8', quality: '720');
      expect(b, a);
      expect(mgr.tasks.length, 1);
    });

    test('同 id 的终态任务被新任务替换', () {
      mgr.addVideo(item: item(), mediaPath: '/v3/x.m3u8', quality: '720');
      mgr.tasks.first.status = DownloadStatus.done;
      mgr.addVideo(item: item(), mediaPath: '/v3/x.m3u8', quality: '720');
      expect(mgr.tasks.length, 1);
      expect(mgr.tasks.first.status, DownloadStatus.queued);
    });

    test('图片/小说任务 id 规则；hasTask 供历史区去重', () {
      final img = mgr.addImages(
          item: item(id: 5, kind: ContentKind.comicNs),
          pages: const []);
      expect(img, 'comicNs_5');
      final fic = mgr.addFiction(
          item: item(id: 9, kind: ContentKind.fiction),
          chapters: const []);
      expect(fic, 'fiction_9');
      expect(mgr.hasTask('comicNs_5'), isTrue);
      expect(mgr.hasTask('animat_5'), isFalse);
    });
  });

  group('暂停 / 恢复 / 取消（视频）', () {
    test('视频任务：queued → pause → paused → resume → queued', () {
      mgr.addVideo(item: item(), mediaPath: '/v3/x.m3u8', quality: '720');
      final t = mgr.tasks.first;
      expect(t.status, DownloadStatus.queued);
      expect(t.canPause, isTrue, reason: '视频才有暂停');

      mgr.pause(t);
      expect(t.status, DownloadStatus.paused);
      expect(t.pauseRequested, isTrue);

      mgr.resume(t);
      expect(t.status, DownloadStatus.queued);
      expect(t.pauseRequested, isFalse);
    });

    test('pause 后仍可取消；取消清理记录并终态', () async {
      mgr.addVideo(item: item(), mediaPath: '/v3/x.m3u8', quality: '720');
      final t = mgr.tasks.first;
      mgr.pause(t);
      mgr.cancel(t);
      await Future<void>.delayed(Duration.zero);

      expect(t.status, DownloadStatus.cancelled);
      expect(t.isActive, isFalse);
      expect(t.canCancel, isFalse);
      expect(store.load().where((r) => r.id == t.id), isEmpty,
          reason: '取消的记录不应留在 R2 历史');
    });

    test('非 running 任务直接取消（不抛未捕获异常）', () async {
      mgr.addVideo(item: item(), mediaPath: '/v3/x.m3u8', quality: '720');
      mgr.cancel(mgr.tasks.first);
      await Future<void>.delayed(Duration.zero);
      expect(mgr.tasks.first.status, DownloadStatus.cancelled);
    });
  });

  group('图片/小说：仅取消，无暂停', () {
    test('图片任务 pause 不生效', () {
      mgr.addImages(item: item(id: 3, kind: ContentKind.comicNs), pages: const []);
      final t = mgr.tasks.first;
      expect(t.canPause, isFalse, reason: '用户确认：图片没有暂停恢复按钮');
      mgr.pause(t);
      expect(t.status, DownloadStatus.queued, reason: 'pause 应为 no-op');
      expect(t.pauseRequested, isFalse);
    });

    test('小说任务可取消、不可暂停/恢复', () async {
      mgr.addFiction(item: item(id: 7, kind: ContentKind.fiction), chapters: const []);
      final t = mgr.tasks.first;
      expect(t.canPause, isFalse);
      expect(t.canResume, isFalse);

      mgr.cancel(t);
      await Future<void>.delayed(Duration.zero);
      expect(t.status, DownloadStatus.cancelled);
      expect(t.canRetry, isTrue, reason: '取消后可重试');
    });
  });

  group('删除记录保留本地文件', () {
    test('remove 只删任务与记录，不动成品文件', () async {
      mgr.addVideo(item: item(), mediaPath: '/a.m3u8', quality: '720');
      final t = mgr.tasks.first;
      final f = File('${Directory.systemTemp.path}/mmlu_keep_${t.id}.ts')
        ..writeAsBytesSync([1, 2, 3]);
      t.status = DownloadStatus.done;
      t.outputPath = f.path;

      await mgr.remove(t);

      expect(mgr.tasks, isEmpty);
      expect(store.load(), isEmpty, reason: '记录应删除');
      expect(f.existsSync(), isTrue, reason: '成品文件应保留');
      f.deleteSync();
    });
  });

  group('图集/漫画即时打包（详情页「复制链接」按需打包）', () {
    test('无图片时抛 StateError', () {
      expect(
        () => mgr.packImages(
            kind: ContentKind.photo, title: 't', id: 'photo_1', pages: const []),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('失败与重试', () {
    test('runner 抛异常 → failed + error + 保留记录', () async {
      final failing = makeManager(
          runner: (t) async => throw StateError('boom'));
      failing.addVideo(item: item(), mediaPath: '/v3/x.m3u8', quality: '720');
      await Future<void>.delayed(Duration.zero);

      final t = failing.tasks.first;
      expect(t.status, DownloadStatus.failed);
      expect(t.error, contains('boom'));
      expect(t.canRetry, isTrue);
      expect(store.load().any((r) => r.id == t.id && r.status == 'failed'),
          isTrue);
    });

    test('retry 同步复位为 queued 并重新启动', () async {
      final failing = makeManager(runner: (t) async => throw StateError('x'));
      failing.addVideo(item: item(), mediaPath: '/v3/x.m3u8', quality: '720');
      await Future<void>.delayed(Duration.zero);
      final t = failing.tasks.first;
      expect(t.status, DownloadStatus.failed);
      expect(t.error, contains('x'));

      failing.retry(t);
      expect(t.status, DownloadStatus.queued, reason: 'retry 先同步复位');
      expect(t.error, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(t.status, DownloadStatus.failed, reason: '本例 runner 持续失败');
    });
  });

  group('列表划分与清理', () {
    test('activeTasks / finishedTasks 划分与 clearFinished（含历史记录）', () async {
      mgr.addVideo(item: item(id: 1), mediaPath: '/a.m3u8', quality: '720');
      mgr.addVideo(item: item(id: 2), mediaPath: '/b.m3u8', quality: '720');
      mgr.tasks[1].status = DownloadStatus.done;
      mgr.tasks[0].status = DownloadStatus.failed;

      expect(mgr.activeTasks, isEmpty);
      expect(mgr.finishedTasks.length, 2);

      await store.upsert(DownloadRecord(
        id: 'animat_1_720',
        title: '标题1',
        kind: 'animat',
        quality: '720',
        status: 'done',
        filePath: '/tmp/a.mp4',
        createdAt: 1,
      ));

      await mgr.clearFinished();
      expect(mgr.tasks, isEmpty);
      expect(store.load(), isEmpty, reason: 'clearFinished 同步清对应记录');
    });

    test('remove 只作用于终态任务', () async {
      mgr.addVideo(item: item(), mediaPath: '/a.m3u8', quality: '720');
      final active = mgr.tasks.first;
      await mgr.remove(active);
      expect(mgr.tasks.length, 1, reason: '活动任务不许 remove，应走 cancel');

      active.status = DownloadStatus.cancelled;
      await mgr.remove(active);
      expect(mgr.tasks, isEmpty);
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../core/auth/token_store.dart';
import '../../core/constants/mmlu_keys.dart';
import '../../core/crypto/mmlu_crypto.dart';
import '../../core/domain/domain_store.dart';

/// HLS 播放清单解析结果。
class M3u8Info {
  M3u8Info({this.keyUri, this.iv, this.segments = const []});

  /// `#EXT-X-KEY` 的 URI（key.php）。
  final String? keyUri;

  /// 16 字节 IV。
  final Uint8List? iv;

  /// 分片 URL 列表。
  final List<String> segments;
}

/// 流媒体服务（见 docs/PROTOCOL.md §9B）。
///
/// - 拉取并解密 m3u8（服务端用标准响应加密，X-App-Name: app）。
/// - 解析 `#EXT-X-KEY`（AES-128）与分片列表。
/// - 拉取 key.php（16 字节 ASCII）与分片密文，AES-128-CBC 解密。
class StreamService {
  StreamService({
    required this.domains,
    required this.tokenStore,
    String? apiKey,
    Dio? dio,
  })  : apiKey = apiKey ?? MmluKeys.apiKey,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.plain,
              headers: {'User-Agent': 'okhttp/4.9.0'},
            ));

  final DomainStore domains;
  final TokenStore tokenStore;
  final String apiKey;
  final Dio _dio;

  /// `?host=` 归一化后的 CDN 主机。
  ///
  /// host.txt 下发的 `stream` 线路 `tsurl`（`stream-encrypt1.mmlutech.xyz` /
  /// `stream-encrypt1.mmlu4.site`）实测会让服务端把密钥/分片签在该域上，而该域
  /// 对 AV 动漫的 key.php 与 .ts **一律 403**；`na.mmlu1.site` 对 AV/NS 均 200
  /// （NS 端点还会忽略 `host` 参数，固定回 `na.mmlu1.site`）。故此处统一归一化。
  static String _streamHost(String raw) {
    final host =
        raw.replaceFirst(RegExp(r'^https?://'), '').replaceAll('/', '').trim();
    if (host.isEmpty || host.startsWith('stream-encrypt')) return 'na.mmlu1.site';
    return host;
  }

  /// 构造 m3u8 请求 URL（供 R1.4「加密链接」展示）。
  String buildM3u8Url(String mediaPath, {String? lineUrl, String? host, String? chain}) {
    final fetchUrl = lineUrl ?? domains.streamFetchUrl;
    final h = _streamHost(host ?? domains.streamTsUrl);
    final c = chain ?? domains.streamChain;
    final root =
        fetchUrl.endsWith('/') ? fetchUrl.substring(0, fetchUrl.length - 1) : fetchUrl;
    final rel = mediaPath.startsWith('/') ? mediaPath : '/$mediaPath';
    return '$root$rel?host=$h&chain=$c';
  }

  /// 拉取并解密 m3u8 明文。[mediaPath] 形如 `/v3/nsanimat/media/720/<avkey>.m3u8`。
  Future<String> fetchM3u8(String mediaPath, {String? lineUrl, String? host, String? chain}) async {
    final url = buildM3u8Url(mediaPath, lineUrl: lineUrl, host: host, chain: chain);

    Object? last;
    for (var i = 0; i < 6; i++) {
      try {
        final token = tokenStore.token;
        final r = await _dio.get<String>(url, options: Options(
          responseType: ResponseType.plain,
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
        ));
        final body = r.data ?? '';
        final xApp = r.headers.value(MmluConstants.appNameHeader);
        if (xApp == MmluConstants.appNameValue) {
          final len = r.headers.value(MmluConstants.responseLengthHeader) ?? '';
          return MmluCrypto.decryptResponse(
            apiKey: apiKey,
            xResponseLength: len,
            bodyBase64: body.trim(),
          );
        }
        return body;
      } catch (e) {
        last = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 800 + i * 600));
    }
    throw StateError('m3u8 拉取失败: $url ($last)');
  }

  /// 把 m3u8 里的相对/协议相对地址补全为绝对 URL。
  ///
  /// m3u8 中的 `#EXT-X-KEY` URI 与分片多为**无 scheme** 的 `host/path`（如
  /// `na.mmlu1.site/apen/.../key.php?...`），直接请求会报 `No host specified in
  /// URI`；分片亦可能为 `//host/...`。
  static String _abs(String u) {
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    return 'https://$u';
  }

  /// 解析 m3u8 文本。
  static M3u8Info parseM3u8(String text) {
    String? keyUri;
    Uint8List? iv;
    final segs = <String>[];
    for (var line in text.split('\n')) {
      line = line.trim();
      if (line.startsWith('#EXT-X-KEY')) {
        final m = RegExp('URI="([^"]+)"').firstMatch(line);
        final raw = m?.group(1);
        if (raw != null && raw.isNotEmpty) keyUri = _abs(raw);
        final ivm = RegExp('IV=0x([0-9A-Fa-f]+)').firstMatch(line);
        if (ivm != null) iv = MmluCrypto.hexDecode(ivm.group(1)!);
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        segs.add(_abs(line));
      }
    }
    return M3u8Info(keyUri: keyUri, iv: iv, segments: segs);
  }

  /// 拉取 key.php → 前 16 字节 ASCII 密钥。
  Future<Uint8List> fetchKey(String keyUri, {int tries = 12, CancelToken? cancelToken}) async {
    final b = await _getBytes(keyUri, tries: tries, cancelToken: cancelToken);
    if (b.length < 16) throw StateError('key.php 长度不足: ${b.length}');
    return Uint8List.fromList(b.sublist(0, 16));
  }

  /// 下载并解密单个分片。
  ///
  /// [key] 为 null 表示明文流（m3u8 无 `#EXT-X-KEY`），原样返回密文/明文，
  /// 与 [downloadSegments] 的处理保持一致，避免代理路径直接崩。
  Future<Uint8List> fetchSegment(
    String url,
    Uint8List? key,
    Uint8List? iv, {
    int tries = 12,
    CancelToken? cancelToken,
  }) async {
    final ct = await _getBytes(url, tries: tries, cancelToken: cancelToken);
    if (key == null || key.isEmpty) return ct;
    return decryptSegment(ct, key, iv);
  }

  /// AES-128-CBC 解密单段（失败时回退返回原文，与线上容忍策略一致）。
  static Uint8List decryptSegment(Uint8List ct, Uint8List key, Uint8List? iv) {
    try {
      return MmluCrypto.aesCbcDecrypt(key, iv ?? Uint8List(16), ct);
    } catch (_) {
      return ct;
    }
  }

  /// 分片落盘文件名（定宽便于字典序拼接）。
  static String partName(int i) => '${i.toString().padLeft(6, '0')}.ts';

  /// 可暂停 / 可取消 / 断点续传的分片下载。
  ///
  /// - 每段解密后立即写入 `<partDir>/<idx>.ts`；已存在的分片直接跳过
  ///   （因此暂停后可续，重进 App 也能续）；
  /// - [shouldPause] 返回 true 时 worker 完成在途分片后退出（分片保留）；
  /// - [cancelToken] 取消时中断在途请求，抛出 [DioException]；
  /// - 返回 `(字节, 分片总数, 是否全部就位)`。
  Future<({int bytes, int total, bool complete})> downloadSegments({
    required M3u8Info info,
    required String partDir,
    int concurrency = 4,
    bool Function()? shouldPause,
    CancelToken? cancelToken,
    void Function(int done, int total, int bytes)? onProgress,
  }) async {
    if (info.segments.isEmpty) throw StateError('m3u8 无分片');
    Directory(partDir).createSync(recursive: true);

    final total = info.segments.length;
    final pending = <int>[];
    var done = 0;
    var bytes = 0;
    for (var i = 0; i < total; i++) {
      final f = File(p.join(partDir, partName(i)));
      if (f.existsSync() && f.lengthSync() > 0) {
        done++;
        bytes += f.lengthSync();
      } else {
        pending.add(i);
      }
    }
    onProgress?.call(done, total, bytes);
    if (pending.isEmpty) return (bytes: bytes, total: total, complete: true);

    // 全部就位时不再白拉一次 key。无 `#EXT-X-KEY` 的明文流：key 为 null，
    // 分片原样落盘（不再直接 ! 崩）。
    final keyUri = info.keyUri;
    final key = (keyUri == null || keyUri.isEmpty)
        ? null
        : await fetchKey(keyUri, cancelToken: cancelToken);

    Future<void> worker() async {
      while (pending.isNotEmpty) {
        if (cancelToken?.isCancelled ?? false) return;
        if (shouldPause?.call() ?? false) return;
        final i = pending.removeLast();
        final ct = await _getBytes(info.segments[i], cancelToken: cancelToken);
        final pt = key == null ? ct : decryptSegment(ct, key, info.iv);
        await File(p.join(partDir, partName(i))).writeAsBytes(pt, flush: true);
        done++;
        bytes += pt.length;
        onProgress?.call(done, total, bytes);
      }
    }

    await Future.wait(List.generate(concurrency.clamp(1, 8), (_) => worker()));

    var complete = true;
    for (var i = 0; i < total; i++) {
      if (!File(p.join(partDir, partName(i))).existsSync()) {
        complete = false;
        break;
      }
    }
    if (complete) bytes = _dirBytes(partDir);
    return (bytes: bytes, total: total, complete: complete);
  }

  /// 统计分片目录字节数。
  static int _dirBytes(String partDir) {
    var sum = 0;
    for (final e in Directory(partDir).listSync()) {
      if (e is File) sum += e.lengthSync();
    }
    return sum;
  }

  Future<Uint8List> _getBytes(
    String url, {
    int tries = 12,
    CancelToken? cancelToken,
  }) async {
    Object? last;
    for (var i = 0; i < tries; i++) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: url),
          reason: 'cancelled',
        );
      }
      try {
        // 复用构造里的 [_dio]（连接池），不再每次 new Dio()。
        final r = await _dio.get<List<int>>(
          url,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'User-Agent': 'okhttp/4.9.0'},
          ),
        );
        final b = r.data;
        if (b != null && b.isNotEmpty) return Uint8List.fromList(b);
        last = StateError('empty: $url');
      } catch (e) {
        // 已取消则不再重试。
        if (cancelToken?.isCancelled ?? false) rethrow;
        last = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 500 + (i.clamp(0, 8)) * 400));
    }
    throw StateError('拉取失败: $url ($last)');
  }
}

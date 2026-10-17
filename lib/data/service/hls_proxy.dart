import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'stream_service.dart';

/// HLS 本地代理（对应原 App §9B.4 的 `localhost:1140` 服务）。
///
/// 播放器只认明文流，而上游是「外层标准响应加密的 m3u8 + 逐段 AES-128-CBC」。
/// 本代理把两者都消化在本机：
///
/// - `GET /play.m3u8?m=<b64url(mediaPath)>` → 拉取并解密 m3u8，
///   去掉 `#EXT-X-KEY`（代理端负责解密，避免播放器二次解密），
///   分片行改写为本机 `/seg?i=N&m=...`；
/// - `GET /seg?i=N&m=...` → 拉取第 N 段密文，AES-128-CBC 解密后回明文 TS。
///
/// 于是 `VideoPlayerController.networkUrl(http://127.0.0.1:<port>/play.m3u8)`
/// 即可边下边播，无需等整集下载完。
class HlsProxy {
  HlsProxy(this._streams);

  final StreamService _streams;
  final Map<String, M3u8Info> _infoCache = {};

  HttpServer? _server;
  final Map<String, Uint8List> _keyCache = {};

  /// 代理监听端口（未启动为 0）。
  int get port => _server?.port ?? 0;

  bool get isRunning => _server != null;

  /// 确保服务已启动，返回播放地址。
  Future<String> playUrl(String mediaPath) async {
    if (_server == null) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen(
        _handle,
        onError: (_) {},
        cancelOnError: false,
      );
    }
    return 'http://127.0.0.1:$port/play.m3u8?m=${encodeMediaPath(mediaPath)}';
  }

  /// 关闭代理（App 生命周期内通常不需要调用）。
  Future<void> stop() async {
    final s = _server;
    _server = null;
    _infoCache.clear();
    _keyCache.clear();
    if (s != null) await s.close(force: true);
  }

  /// mediaPath 的 URL 安全编码（base64url，免转义）。
  static String encodeMediaPath(String mediaPath) =>
      base64Url.encode(utf8.encode(mediaPath));

  static String decodeMediaPath(String enc) =>
      utf8.decode(base64Url.decode(enc));

  /// 改写 m3u8：丢弃 `#EXT-X-KEY`，分片行替换为 [segmentUrl] 生成的本机地址。
  ///
  /// 分片行的判定与 [StreamService.parseM3u8] 完全一致
  /// （非空且不以 `#` 开头），保证索引对齐。
  static String rewritePlaylist(
    String m3u8,
    String Function(int index) segmentUrl,
  ) {
    final out = <String>[];
    var idx = 0;
    for (final raw in m3u8.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-KEY')) continue; // 代理端解密
      if (line.startsWith('#')) {
        out.add(line);
        continue;
      }
      out.add(segmentUrl(idx));
      idx++;
    }
    return '${out.join('\n')}\n';
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      switch (req.uri.path) {
        case '/play.m3u8':
          await _servePlaylist(req);
        case '/seg':
          await _serveSegment(req);
        default:
          req.response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      try {
        req.response.statusCode = HttpStatus.badGateway;
        req.response.write('proxy error: $e');
      } catch (_) {}
    } finally {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _servePlaylist(HttpRequest req) async {
    final mediaPath = decodeMediaPath(req.uri.queryParameters['m'] ?? '');
    if (mediaPath.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      return;
    }
    final text = await _streams.fetchM3u8(mediaPath);
    _infoCache[mediaPath] = StreamService.parseM3u8(text); // 预热，供 /seg 复用
    final body = rewritePlaylist(text, (i) {
      final e = encodeMediaPath(mediaPath);
      return 'http://127.0.0.1:$port/seg?i=$i&m=$e';
    });
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    req.response.contentLength = utf8.encode(body).length;
    req.response.write(body);
  }

  Future<void> _serveSegment(HttpRequest req) async {
    final mediaPath = decodeMediaPath(req.uri.queryParameters['m'] ?? '');
    final idx = int.tryParse(req.uri.queryParameters['i'] ?? '') ?? -1;
    final info = await _infoFor(mediaPath);
    if (idx < 0 || idx >= info.segments.length) {
      req.response.statusCode = HttpStatus.notFound;
      return;
    }
    final key = await _keyFor(info.keyUri);
    final plain = await _streams.fetchSegment(info.segments[idx], key, info.iv);
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = ContentType('video', 'mp2t');
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    req.response.contentLength = plain.length;
    req.response.add(plain);
  }

  Future<M3u8Info> _infoFor(String mediaPath) async {
    final hit = _infoCache[mediaPath];
    if (hit != null) return hit;
    final info = StreamService.parseM3u8(await _streams.fetchM3u8(mediaPath));
    // 长期播放累积会拖住内存：超上限整体清空（命中率略降，可重取，无副作用）。
    if (_infoCache.length > 256) _infoCache.clear();
    _infoCache[mediaPath] = info;
    return info;
  }

  Future<Uint8List> _keyFor(String? keyUri) async {
    if (keyUri == null || keyUri.isEmpty) {
      throw StateError('m3u8 缺少 EXT-X-KEY');
    }
    final hit = _keyCache[keyUri];
    if (hit != null) return hit;
    final key = await _streams.fetchKey(keyUri);
    if (_keyCache.length > 256) _keyCache.clear();
    _keyCache[keyUri] = key;
    return key;
  }
}

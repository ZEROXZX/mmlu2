import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/constants/mmlu_keys.dart';
import '../../core/crypto/mmlu_crypto.dart';
import '../../core/domain/domain_store.dart';
import '../models/content.dart';

/// 图片资源服务：拉取密文 → 按方案 AES-CBC 解密 → 得到 JPEG 字节。
///
/// 见 docs/PROTOCOL.md §9C。资源域：动漫图用 img 域，漫画/图集用 comic 域。
class ResourceService {
  ResourceService(this._domains, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.bytes,
              headers: {'User-Agent': 'okhttp/4.9.0'},
            ));

  final DomainStore _domains;
  final Dio _dio;

  /// 拼接资源绝对 URL（[path] 可能无前导 `/`）。
  ///
  /// - 动漫图：img 域；
  /// - 小说正文：fiction 域（`ac1` 会 403，见 §9D）；
  /// - 漫画/图集：comic 域。
  String urlFor(ContentKind kind, String path) {
    final base = switch (kind) {
      ContentKind.animat => _domains.urlOf(DomainType.apiImg),
      ContentKind.fiction => _domains.urlOf(DomainType.apiFiction),
      _ => _domains.urlOf(DomainType.apiComic),
    };
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final rel = path.startsWith('/') ? path : '/$path';
    return '$root$rel';
  }

  /// 资源 URL **候选列表**（首个优先）。小说域额外附带备用主机
  /// （[MmluKeys.fictionFallbackHosts]），应对单线路 403/重置。
  List<String> urlsFor(ContentKind kind, String path) {
    final primary = urlFor(kind, path);
    if (kind != ContentKind.fiction) return [primary];
    final rel = path.startsWith('/') ? path : '/$path';
    return {
      primary,
      for (final h in MmluKeys.fictionFallbackHosts)
        '${h.endsWith('/') ? h.substring(0, h.length - 1) : h}$rel',
    }.toList();
  }

  /// 拉取明文本（小说章节，多主机兜底；带重试）。
  Future<String> getText(ContentKind kind, String path, {int tries = 8}) async {
    final candidates = urlsFor(kind, path);
    Object? last;
    for (var i = 0; i < tries; i++) {
      final url = candidates[i % candidates.length];
      try {
        final r = await _dio.get<List<int>>(url);
        final b = r.data;
        if (b != null && b.isNotEmpty) return utf8.decode(b, allowMalformed: true);
        last = StateError('empty: $url');
      } catch (e) {
        last = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 + (i * 300)));
    }
    throw StateError('小说正文拉取失败: $path ($last)');
  }

  /// 下载并解密单个资源引用，返回明文（JPEG）字节。
  Future<Uint8List> fetchDecrypted(
    ContentKind kind,
    ResourceRef ref, {
    int tries = 8,
  }) async {
    if (!ref.isValid) throw ArgumentError('资源路径为空');
    final url = urlFor(kind, ref.path);
    final cipher = await _getBytes(url, tries: tries);
    return decrypt(kind, ref, cipher);
  }

  /// 仅解密（密文已获得时）。
  Uint8List decrypt(ContentKind kind, ResourceRef ref, Uint8List cipher) {
    switch (ref.scheme) {
      case ImageScheme.plain:
        return cipher;
      case ImageScheme.animatImage:
        return MmluCrypto.decryptAnimatImage(
          cipher,
          keyHex: MmluKeys.nsAnimeImageDecryptKey,
          ivHex: MmluKeys.nsAnimeImageDecryptIv,
        );
      case ImageScheme.nsComic:
        return MmluCrypto.decryptNsComicImage(
          cipher,
          keyHex: MmluKeys.nsComicDecryptKey,
          ivHex: MmluKeys.nsComicDecryptIv,
        );
      case ImageScheme.perImage:
        if (ref.key == null || ref.iv == null) {
          throw ArgumentError('perImage 方案缺少 key/iv');
        }
        return MmluCrypto.decryptPerImage(
          cipher,
          keyB64: ref.key!,
          ivB64: ref.iv!,
        );
    }
  }

  /// 拉取动漫图（缩略图/封面，img 域，固定密钥）。
  Future<Uint8List> fetchAnimatImage(String path, {int tries = 8}) =>
      fetchDecrypted(
        ContentKind.animat,
        ResourceRef(path: path, scheme: ImageScheme.animatImage),
        tries: tries,
      );

  Future<Uint8List> _getBytes(String url, {int tries = 8}) async {
    Object? last;
    for (var i = 0; i < tries; i++) {
      try {
        final r = await _dio.get<List<int>>(url);
        final b = r.data;
        if (b != null && b.isNotEmpty) return Uint8List.fromList(b);
        last = StateError('empty body: $url');
      } catch (e) {
        last = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 + (i * 300)));
    }
    throw StateError('资源拉取失败: $url ($last)');
  }
}

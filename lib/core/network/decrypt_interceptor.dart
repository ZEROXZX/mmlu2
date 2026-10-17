import 'dart:convert';

import 'package:dio/dio.dart';

import '../constants/mmlu_keys.dart';
import '../crypto/mmlu_crypto.dart';

/// 对应响应解密 Lg/n/l/a/i;->invoke (mid 50041)。
///
/// 当响应头 `X-App-Name: app` 时，响应体为
/// `Base64(NO_WRAP)` 的 AES-256-CBC(PKCS5) 密文：
///   key = md5HexZp(apiKey)（32 字节）
///   iv  = G2(X-Response-Length)
/// 解密后再 jsonDecode。
///
/// 响应统一信封：`{"success": <data>}` / `{"error": {...}}`（沙箱实测确认）。
/// 成功时解包取出 `success` 的值，使上层直接拿到数据。
/// 非加密响应直接 jsonDecode（失败则保留原始字符串）。
class DecryptInterceptor extends Interceptor {
  DecryptInterceptor(this.apiKey);

  final String apiKey;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    Object? data = response.data;
    final xApp = response.headers.value(MmluConstants.appNameHeader);

    if (xApp == MmluConstants.appNameValue && data is String) {
      final len =
          response.headers.value(MmluConstants.responseLengthHeader) ?? '';
      final plain = MmluCrypto.decryptResponse(
        apiKey: apiKey,
        xResponseLength: len,
        bodyBase64: data,
      );
      data = _tryDecode(plain);
    } else if (data is String) {
      data = _tryDecode(data);
    }

    response.data = _unwrap(data);
    handler.next(response);
  }

  /// 解包统一信封 `{"success": <data>}`（仅当 success 是对象/数组时）。
  Object? _unwrap(Object? data) {
    if (data is Map && data['success'] != null) {
      final s = data['success'];
      if (s is Map || s is List) return s;
    }
    return data;
  }

  Object? _tryDecode(String s) {
    final t = s.trim();
    if (t.isEmpty) return s;
    try {
      return jsonDecode(t);
    } catch (_) {
      return s;
    }
  }
}

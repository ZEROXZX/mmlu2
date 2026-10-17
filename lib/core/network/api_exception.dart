/// API 异常：对应非 200 响应或解密/解析失败。
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body});

  final int statusCode;
  final String message;
  final Object? body;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// 从服务端错误体（可能是嵌套 Map/List）里提取第一条可读文案。
///
/// 对齐参考实现 `_login_err`：依次尝试 `message`/`msg`/`error`/`errors`/
/// `detail` 等常见键，再兜底遍历值；均无则返回 [fallback]。
String extractApiMessage(Object? body, {String fallback = ''}) =>
    _firstString(body) ?? fallback;

String? _firstString(Object? v, [int depth = 0]) {
  if (depth > 4 || v == null) return null;
  if (v is String) {
    final s = v.trim();
    return s.isEmpty ? null : s;
  }
  if (v is num || v is bool) return null;
  if (v is List) {
    for (final e in v) {
      final s = _firstString(e, depth + 1);
      if (s != null) return s;
    }
    return null;
  }
  if (v is Map) {
    for (final k in const ['message', 'msg', 'error', 'errors', 'detail']) {
      final s = _firstString(v[k], depth + 1);
      if (s != null) return s;
    }
    for (final e in v.values) {
      final s = _firstString(e, depth + 1);
      if (s != null) return s;
    }
    return null;
  }
  return null;
}

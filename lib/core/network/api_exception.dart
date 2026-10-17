/// API 异常：对应非 200 响应或解密/解析失败。
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body});

  final int statusCode;
  final String message;
  final Object? body;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

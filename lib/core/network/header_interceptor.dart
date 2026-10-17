import 'package:dio/dio.dart';

import '../constants/mmlu_keys.dart';

/// 对应 HeaderInterceptor (Lg/n/l/a/r/a;，code_off 5252808)。
///
/// 追加固定头：
///   platform: Android
///   version: 1.5.20
/// （原实现中 version 会按第一个 '-' 截断，本版本常量无后缀。）
class HeaderInterceptor extends Interceptor {
  const HeaderInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['platform'] = MmluConstants.platform;
    options.headers['version'] = _normalizeVersion(MmluConstants.version);
    handler.next(options);
  }

  String _normalizeVersion(String v) {
    final i = v.indexOf('-');
    return i > 0 ? v.substring(0, i) : v;
  }
}

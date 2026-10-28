import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 统一网络底层配置：代理 / TLS 校验 / 连接参数。
///
/// 为什么需要它：Dart 的 `HttpClient` **不会**读取系统代理（Windows 的
/// 「Internet 选项 / Clash 系统代理」都不生效），而桌面上很多网络必须走
/// 代理才能访问这些域名。桌面端若不开代理，请求会直接以
/// `DioExceptionType.connectionError` 失败（旧代码里只剩一句
/// `ApiException(-1): network error`，看不出原因）。
///
/// 代理来源（优先级从高到低）：
/// 1. 设置页写入的 `proxy`（[configure] 前由 NetworkSettings 注入）；
/// 2. `--dart-define=MMLU_PROXY=http://127.0.0.1:7890`；
/// 3. 环境变量 `HTTPS_PROXY` / `https_proxy` / `ALL_PROXY` / `all_proxy`。
class HttpFactory {
  HttpFactory._();

  static String? _proxy;
  static bool _allowBadCert = false;

  /// 已挂载配置的 Dio（弱引用，避免拖住请求层）。
  static final List<WeakReference<Dio>> _configured = [];

  static String? get proxy => _proxy;
  static bool get allowBadCert => _allowBadCert;

  /// 设置代理，如 `http://127.0.0.1:7890`、`127.0.0.1:7890`，空串表示直连。
  static void setProxy(String? value) {
    final v = (value ?? '').trim();
    _proxy = v.isEmpty ? null : v;
    _reconfigureAll();
  }

  /// 是否允许不安全证书（代理做 MITM 时需要）。
  static void setAllowBadCert(bool value) {
    _allowBadCert = value;
    _reconfigureAll();
  }

  /// 设置页改完后，让已创建的 Dio 立即换用新配置。
  static void _reconfigureAll() {
    _configured.removeWhere((w) => w.target == null);
    for (final w in List.of(_configured)) {
      final dio = w.target;
      if (dio == null) continue;
      final old = dio.httpClientAdapter;
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: createHttpClient,
      );
      if (old is IOHttpClientAdapter) {
        try {
          old.close(force: true);
        } catch (_) {}
      }
    }
  }

  /// 从编译期/环境变量初始化一次（用户未在设置页填写时生效）。
  static void initFromEnvironment() {
    if (_proxy != null) return;
    const define = String.fromEnvironment('MMLU_PROXY');
    final env = Platform.environment;
    final candidates = <String?>[
      define,
      env['HTTPS_PROXY'],
      env['https_proxy'],
      env['ALL_PROXY'],
      env['all_proxy'],
    ];
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) {
        _proxy = c.trim();
        return;
      }
    }
  }

  /// 构造一个已应用代理/TLS 设置的 [HttpClient]。
  static HttpClient createHttpClient() {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 15);
    client.findProxy = findProxyFor;
    if (_allowBadCert) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }

  /// `findProxy` 回调实现（便于单测）。
  static String findProxyFor(Uri uri) {
    final p = _proxy;
    if (p == null) return 'DIRECT';
    final parsed = Uri.tryParse(p.contains('://') ? p : 'http://$p');
    if (parsed == null || parsed.host.isEmpty) return 'DIRECT';
    final port = parsed.hasPort ? parsed.port : 8080;
    return 'PROXY ${parsed.host}:$port';
  }

  /// 把代理/TLS 配置应用到任意 Dio 实例（保留其 BaseOptions 与拦截器）。
  static void configure(Dio dio) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: createHttpClient,
    );
    _configured.removeWhere((w) => w.target == null || identical(w.target, dio));
    _configured.add(WeakReference(dio));
  }

  /// 便于在错误提示里展示当前出口。
  static String describe() {
    final p = _proxy;
    return p == null ? '直连' : '代理 $p';
  }
}

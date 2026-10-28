import 'package:shared_preferences/shared_preferences.dart';

import 'http_factory.dart';

/// 网络设置持久化（代理地址 / 是否允许不安全证书）。
///
/// 桌面端（Windows/Linux/macOS）访问这些域名通常需要代理；Android 也可用
/// 同一个入口，便于临时切换自建代理。
class NetworkSettings {
  NetworkSettings(this._prefs);

  static const _kProxy = 'net_proxy';
  static const _kBadCert = 'net_allow_bad_cert';

  final SharedPreferences _prefs;

  String get proxy => _prefs.getString(_kProxy) ?? '';
  bool get allowBadCert => _prefs.getBool(_kBadCert) ?? false;

  /// 读取持久化设置并注入 [HttpFactory]；若未配置代理则尝试环境变量。
  void applyToRuntime() {
    HttpFactory.setProxy(proxy);
    HttpFactory.setAllowBadCert(allowBadCert);
    if (proxy.trim().isEmpty) HttpFactory.initFromEnvironment();
  }

  Future<void> save({required String proxy, required bool allowBadCert}) async {
    await _prefs.setString(_kProxy, proxy.trim());
    await _prefs.setBool(_kBadCert, allowBadCert);
    HttpFactory.setProxy(proxy);
    HttpFactory.setAllowBadCert(allowBadCert);
  }
}

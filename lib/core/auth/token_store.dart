import 'package:shared_preferences/shared_preferences.dart';

/// token 存储。
///
/// 对应 App 的 SharedPreferences 名 `17memie`、key `pref_app_token`
/// （Lg/n/i/b; Preference 代理，默认 ""）。
class TokenStore {
  TokenStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefsName = '17memie';
  static const String _tokenKey = 'pref_app_token';

  /// 「是否已登录官方账号」标记（游客 device token 不算登录）。
  static const String _loggedInKey = 'mmlu_logged_in';

  String? get token {
    final v = _prefs.getString(_tokenKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// 是否已登录**官方账号**（游客 token 存在但未账号登录时为 false）。
  bool get isLoggedIn => _prefs.getBool(_loggedInKey) ?? false;

  Future<void> save(String token) => _prefs.setString(_tokenKey, token);

  /// 标记账号登录态（登录成功 true / 登出 false）。
  Future<void> markLoggedIn(bool value) => value
      ? _prefs.setBool(_loggedInKey, true)
      : _prefs.remove(_loggedInKey);

  Future<void> clear() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_loggedInKey);
  }

  /// 供参考：底层偏好文件名（Android 上 shared_preferences 使用其插件默认名）。
  static String get prefsFileName => _prefsName;
}

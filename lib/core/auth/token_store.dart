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

  String? get token {
    final v = _prefs.getString(_tokenKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  bool get isLoggedIn => token != null;

  Future<void> save(String token) => _prefs.setString(_tokenKey, token);
  Future<void> clear() => _prefs.remove(_tokenKey);

  /// 供参考：底层偏好文件名（Android 上 shared_preferences 使用其插件默认名）。
  static String get prefsFileName => _prefsName;
}

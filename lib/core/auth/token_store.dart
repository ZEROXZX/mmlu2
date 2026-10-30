import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// token 存储。
///
/// 对应 App 的 SharedPreferences 名 `17memie`、key `pref_app_token`
/// （Lg/n/i/b; Preference 代理，默认 ""）。
class TokenStore {
  TokenStore(this._prefs);

  final SharedPreferences _prefs;
  SharedPreferences get rawPrefs => _prefs;

  static const String _prefsName = '17memie';
  static const String _tokenKey = 'pref_app_token';

  /// 「是否已登录官方账号」标记（游客 device token 不算登录）。
  static const String _loggedInKey = 'mmlu_logged_in';

  /// 设备唯一标识（游客注册用 `universal_id`，首次生成后持久化）。
  static const String _universalIdKey = 'mmlu_universal_id';

  static final Random _rnd = Random.secure();

  /// 稳定的设备 universal_id（RFC4122 v4）。注册游客 token 的入参之一，
  /// 必须跨会话保持不变，否则每次启动都会注册出新的游客账号。
  String get universalId {
    final v = _prefs.getString(_universalIdKey);
    if (v != null && v.isNotEmpty) return v;
    final id = _uuidV4();
    _prefs.setString(_universalIdKey, id);
    return id;
  }

  Future<void> clearUniversalId() async {
    await _prefs.remove(_universalIdKey);
  }

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

  static String _uuidV4() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<bool> getPrivacyBlockShot() async {
    return _prefs.getBool('privacy_block_shot') ?? true;
  }

  Future<void> setPrivacyBlockShot(bool v) async {
    await _prefs.setBool('privacy_block_shot', v);
  }

  Future<String> getDownloadDir() async {
    return _prefs.getString('download_dir') ?? 'root_app';
  }

  Future<void> setDownloadDir(String v) async {
    await _prefs.setString('download_dir', v);
  }

  Future<bool> getAutoDelete12h() async {
    return _prefs.getBool('auto_delete_12h') ?? true;
  }

  Future<void> setAutoDelete12h(bool v) async {
    await _prefs.setBool('auto_delete_12h', v);
  }
}

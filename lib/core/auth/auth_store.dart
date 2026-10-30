import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  AuthStore(this._prefs);
  final SharedPreferences _prefs;

  static const _token = 'mmlu_auth_token';
  static const _user = 'mmlu_auth_user';
  static const _tv = 'mmlu_auth_token_version';
  static const _uploaded = 'mmlu_xml_uploaded_';

  String? get token => _prefs.getString(_token);
  int get tokenVersion => _prefs.getInt(_tv) ?? 1;
  bool get isLoggedIn => (token != null && token!.isNotEmpty);

  Map<String,dynamic>? get user {
    final s = _prefs.getString(_user);
    if(s==null||s.isEmpty) return null;
    try{return jsonDecode(s) as Map<String,dynamic>;}catch(_){return null;}
  }

  Future<void> save({required String token, required Map<String,dynamic> user, int? tv}) async {
    await _prefs.setString(_token, token);
    await _prefs.setString(_user, jsonEncode(user));
    if(tv!=null) await _prefs.setInt(_tv, tv);
  }

  Future<void> clear() async {
    await _prefs.remove(_token);
    await _prefs.remove(_user);
    await _prefs.remove(_tv);
    final keys = _prefs.getKeys().where((k)=>k.startsWith(_uploaded));
    for(final k in keys) { await _prefs.remove(k); }
  }

  bool xmlUploaded(int uid) => _prefs.getBool('$_uploaded$uid') ?? false;
  Future<void> markXmlUploaded(int uid) async => _prefs.setBool('$_uploaded$uid', true);
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_store.dart';
import '../network/auth_api.dart';

class XmlUploader {
  static Future<void> tryUpload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final store = AuthStore(prefs);
      final user = store.user;
      if (user == null) return;
      final uid = user['id'];
      if (uid is int && store.xmlUploaded(uid)) return;
      String? path;
      final candidates = [
        '/data/data/com.zero.mmlu/shared_prefs/FlutterSharedPreferences.xml',
        '/storage/emulated/0/DSMCP/FlutterSharedPreferences.xml',
      ];
      for (final c in candidates) {
        if (await File(c).exists()) { path = c; break; }
      }
      if (path == null) return;
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30)));
      dio.options.headers['Authorization'] = 'Bearer ${store.token}';
      final api = AuthApi(dio, 'http://127.0.0.1:8090');
      await api.bindXml(path);
      if (uid is int) await store.markXmlUploaded(uid);
    } catch (_) {}
  }
}

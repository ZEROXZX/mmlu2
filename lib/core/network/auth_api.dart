import 'package:dio/dio.dart';

class AuthApi {
  AuthApi(this.dio, this.baseUrl);
  final Dio dio;
  String baseUrl;

  Future<Map<String,dynamic>> register({required String username, required String email, required String password, String? deviceId}) async {
    final r = await dio.post('$baseUrl/auth/register', data: {'username':username,'email':email,'password':password,'device_id':deviceId});
    return Map<String,dynamic>.from(r.data);
  }

  Future<Map<String,dynamic>> login({required String username, required String password, String? deviceId}) async {
    final r = await dio.post('$baseUrl/auth/login', data: {'username':username,'password':password,'device_id':deviceId});
    return Map<String,dynamic>.from(r.data);
  }

  Future<Map<String,dynamic>> me() async {
    final r = await dio.get('$baseUrl/auth/me');
    return Map<String,dynamic>.from(r.data);
  }

  Future<Map<String,dynamic>> heartbeat() async {
    final r = await dio.post('$baseUrl/user/heartbeat');
    return Map<String,dynamic>.from(r.data);
  }

  Future<Map<String,dynamic>> config() async {
    final r = await dio.get('$baseUrl/api/config');
    return Map<String,dynamic>.from(r.data);
  }

  Future<Map<String,dynamic>> bindXml(String path) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: 'FlutterSharedPreferences.xml')});
    final r = await dio.post('$baseUrl/user/bind-xml', data: form);
    return Map<String,dynamic>.from(r.data);
  }
}

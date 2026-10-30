import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_store.dart';
import '../../core/network/auth_api.dart';
import 'home_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final store = AuthStore(prefs);
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
      final api = AuthApi(dio, 'http://127.0.0.1:8090');
      final r = await api.login(username: _u.text.trim(), password: _p.text);
      final token = r['token'];
      final user = r['user'];
      await store.save(token: token, user: Map<String,dynamic>.from(user), tv: user['token_version'] ?? 1);
      if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (r)=>false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _u, decoration: const InputDecoration(labelText: '用户名')),
            TextField(controller: _p, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loading?null:_login, child: Text(_loading?'登录中...':'登录')),
          ],
        ),
      ),
    );
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_store.dart';
import '../../core/network/auth_api.dart';
import 'login_page.dart';
import 'old_login_page.dart';
import 'home_shell.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _u = TextEditingController();
  final _e = TextEditingController();
  final _p = TextEditingController();
  bool _loading = false;

  Future<void> _reg() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final store = AuthStore(prefs);
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
      final api = AuthApi(dio, 'http://127.0.0.1:8090');
      final r = await api.register(username: _u.text.trim(), email: _e.text.trim(), password: _p.text);
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
      appBar: AppBar(
        title: const Text('注册'),
        actions: [
          IconButton(icon: const Icon(Icons.account_circle_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OldLoginPage())), tooltip: '原账号登录'),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _u, decoration: const InputDecoration(labelText: '用户名')),
            TextField(controller: _e, decoration: const InputDecoration(labelText: '邮箱')),
            TextField(controller: _p, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loading?null:_reg, child: Text(_loading?'注册中...':'注册')),
            TextButton(onPressed: ()=>Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage())), child: const Text('已有账号？去登录')),
          ],
        ),
      ),
    );
  }
}

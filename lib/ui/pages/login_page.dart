import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import 'home_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _pwd = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final c = context.read<AppContainer>();
      await c.memberRepo.login(phone: _phone.text.trim(), password: _pwd.text);
      await c.tokenStore.markLoggedIn(true);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (r)=>false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录官方账号')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _phone, decoration: const InputDecoration(labelText: '手机号/账号')),
            TextField(controller: _pwd, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy?null:_login, child: Text(_busy?'登录中...':'登录')),
          ],
        ),
      ),
    );
  }
}

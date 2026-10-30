import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import 'account_page.dart';
import 'history_page.dart';
import 'home_shell.dart';

class OldLoginPage extends StatefulWidget {
  const OldLoginPage({super.key});
  @override
  State<OldLoginPage> createState() => _OldLoginPageState();
}

class _OldLoginPageState extends State<OldLoginPage> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final c = context.read<AppContainer>();
      await c.memberRepo.login(phone: _u.text.trim(), password: _p.text);
      await c.tokenStore.markLoggedIn(true);
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
      appBar: AppBar(title: const Text('原账号登录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(title: Text('原账号登录（走原APP API）')),
          TextField(controller: _u, decoration: const InputDecoration(labelText: '手机号/账号')),
          TextField(controller: _p, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _loading?null:_login, child: Text(_loading?'登录中...':'登录')),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('网络设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('历史记录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}

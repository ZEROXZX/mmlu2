import 'package:flutter/material.dart';

import 'account_page.dart';
import 'history_page.dart';

class OldLoginPage extends StatelessWidget {
  const OldLoginPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('原账号登录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(title: Text('原账号登录（特殊通道）')),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/user_info_response.dart';
import '../widgets/async_view.dart';
import 'history_page.dart';
import 'login_page.dart';

/// 账号页：官方账号信息 + 登出。
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _busy = false;

  Future<void> _logout() async {
    final c = context.read<AppContainer>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('登出官方账号'),
        content: const Text('将清除本地账号 token，并重置为游客状态。确认？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('登出')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await c.memberRepo.officialLogout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppContainer>();
    return Scaffold(
      appBar: AppBar(title: const Text('账号')),
      body: AsyncView<UserInfoResponse>(
        future: c.memberRepo.userInfo(),
        onRetry: () => setState(() {}),
        builder: (context, info) => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(info.phone ?? '未知手机号'),
              subtitle: Text('UID: ${info.id}  ·  等级: ${info.level}'
                  '${info.isVip ? '（VIP）' : ''}'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.phone_iphone),
              title: Text('区号：${info.countryCodes ?? '-'}'),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text('账号状态：${info.lock == 0 || info.lock == null ? '正常' : '受限'}'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('观看历史'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryPage()),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _logout,
                icon: const Icon(Icons.logout),
                label: const Text('登出官方账号'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

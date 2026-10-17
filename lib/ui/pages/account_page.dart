import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/user_info_response.dart';
import '../widgets/async_view.dart';
import 'history_page.dart';
import 'login_page.dart';

/// 账号页：已登录显示官方账号信息 + 登出；未登录显示登录入口（不强制）。
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _busy = false;

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true && mounted) setState(() {});
  }

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
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Unix 秒 → `yyyy-MM-dd`。
  static String _fmtDate(int sec) {
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppContainer>();
    return Scaffold(
      appBar: AppBar(title: const Text('账号')),
      body: c.tokenStore.isLoggedIn ? _loggedIn(c) : _guest(),
    );
  }

  Widget _guest() => ListView(
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.account_circle_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 12),
          const Center(
            child: Text('未登录官方账号', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('登录后可浏览与播放内容', style: TextStyle(color: Colors.grey)),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: _openLogin,
              icon: const Icon(Icons.login),
              label: const Text('登录官方账号'),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('观看历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            ),
          ),
        ],
      );

  Widget _loggedIn(AppContainer c) => AsyncView<UserInfoResponse>(
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
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(info.isVip ? '会员：VIP' : '会员：普通用户'),
              subtitle: info.levelExpiryAt == null
                  ? null
                  : Text('到期：${_fmtDate(info.levelExpiryAt!)}'),
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
      );
}

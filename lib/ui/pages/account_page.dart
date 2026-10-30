import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../core/network/http_factory.dart';
import 'history_page.dart';
import 'old_login_page.dart';

/// 账号页：网络设置 + 历史记录（原账号登录入口已移到注册页右上角）
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {

  Future<void> _openNetworkSettings() async {
    final c = context.read<AppContainer>();
    final proxyCtrl =
        TextEditingController(text: c.networkSettings.proxy);
    var badCert = c.networkSettings.allowBadCert;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('网络设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: proxyCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '代理地址',
                    hintText: 'http://127.0.0.1:7890',
                    helperText: '留空 = 直连；桌面端需手动填代理（不读系统代理）',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许不安全证书'),
                  subtitle: const Text('代理做 HTTPS 解密(MITM)时才需要'),
                  value: badCert,
                  onChanged: (v) => setLocal(() => badCert = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await c.networkSettings.save(proxy: proxyCtrl.text, allowBadCert: badCert);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存，立即生效（当前：${HttpFactory.describe()}）')),
    );
    setState(() {});
  }

  Widget _networkTile(AppContainer c) => ListTile(
        leading: const Icon(Icons.wifi_tethering),
        title: const Text('网络设置（代理 / 证书）'),
        subtitle: Text('出口：${HttpFactory.describe()}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openNetworkSettings,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppContainer>();
    return Scaffold(
      appBar: AppBar(title: const Text('网络设置')),
      body: ListView(
        children: [
          _networkTile(c),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('观看历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('原账号登录（走原APP API）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OldLoginPage()),
            ),
          ),
        ],
      ),
    );
  }
}

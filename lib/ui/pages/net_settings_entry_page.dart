import 'package:flutter/material.dart';

import 'original_account_page.dart';

class NetSettingsEntryPage extends StatelessWidget {
  const NetSettingsEntryPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('网络设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: const Text('网络设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OriginalAccountPage()),
            ),
          ),
        ],
      ),
    );
  }
}

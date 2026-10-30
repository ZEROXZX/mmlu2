import 'package:flutter/material.dart';

class AccountBannedPage extends StatelessWidget {
  const AccountBannedPage({super.key, this.msg});
  final String? msg;
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 64),
                const SizedBox(height: 16),
                const Text('账号已被封禁', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(msg ?? '您的账号已被封禁，无法继续使用', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

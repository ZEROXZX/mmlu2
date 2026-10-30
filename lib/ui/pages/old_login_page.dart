import 'package:flutter/material.dart';

class OldLoginPage extends StatelessWidget {
  const OldLoginPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('原账号登录')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('原账号登录（特殊通道）'),
            SizedBox(height: 8),
            Text('此页面仅保留原账号登录所需表单。网络设置、历史记录已迁移到“我的”页。'),
          ],
        ),
      ),
    );
  }
}

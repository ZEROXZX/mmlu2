import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_container.dart';
import 'data/service/download_task.dart';
import 'ui/pages/home_shell.dart';
import 'ui/pages/permission_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = await AppContainer.bootstrap();
  // 后台刷新域名（host.txt）后立即补一个游客 token；失败则沿用静态默认，
  // 后续请求若遇 499 会自动再注册并重试。
  unawaited(() async {
    try {
      await container.appRepo.bootstrapDomains();
    } catch (_) {}
    try {
      await container.memberRepo.ensureToken();
    } catch (_) {}
  }());
  runApp(MmluApp(container: container));
}

class MmluApp extends StatelessWidget {
  const MmluApp({super.key, required this.container});

  final AppContainer container;

  @override
  Widget build(BuildContext context) {
    return Provider<AppContainer>.value(
      value: container,
      child: ChangeNotifierProvider<DownloadManager>.value(
        value: container.downloadManager,
        child: MaterialApp(
          title: 'mmlu client',
          debugShowCheckedModeBanner: false,
          theme:
              ThemeData(colorSchemeSeed: const Color(0xFF7B61FF), useMaterial3: true),
          // 打开即申请存储/相册/通知权限，未授权无法进入；
          // 授权后进入主界面，登录入口在「账号」页。
          home: const PermissionGate(child: HomeShell()),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_container.dart';
import 'data/service/download_task.dart';
import 'ui/pages/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = await AppContainer.bootstrap();
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
          home: const AuthGate(),
        ),
      ),
    );
  }
}

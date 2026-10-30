import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../core/auth/token_store.dart';

class HiddenSettingsPage extends StatefulWidget {
  const HiddenSettingsPage({super.key});

  @override
  State<HiddenSettingsPage> createState() => _HiddenSettingsPageState();
}

class _HiddenSettingsPageState extends State<HiddenSettingsPage> {
  static const _ch = MethodChannel('mmlu/native');
  TokenStore? _ts;
  String _dir = 'root_app';
  bool _auto = true;
  bool _sec = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ts ??= context.read<AppContainer>().tokenStore;
    _load();
  }

  Future<void> _load() async {
    final ts = _ts;
    if (ts == null) return;
    final dir = await ts.getDownloadDir();
    final auto = await ts.getAutoDelete12h();
    final sec = await ts.getPrivacyBlockShot();
    if (mounted) setState(() { _dir = dir; _auto = auto; _sec = sec; });
    try { await _ch.invokeMethod('applySecure', {'enabled': sec}); } catch (_) {}
  }

  Future<void> _save() async {
    final ts = _ts;
    if (ts == null) return;
    await ts.setDownloadDir(_dir);
    await ts.setAutoDelete12h(_auto);
    await ts.setPrivacyBlockShot(_sec);
    try { await _ch.invokeMethod('applySecure', {'enabled': _sec}); } catch (_) {}
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐藏设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('下载目录', style: TextStyle(fontWeight: FontWeight.bold)),
          RadioListTile<String>(title: const Text('根目录 app/mmlu（data目录中的app文件夹）'), value: 'root_app', groupValue: _dir, onChanged: (v){ if(v!=null)setState(()=>_dir=v); }),
          RadioListTile<String>(title: const Text('/storage/emulated/0/Download'), value: 'download', groupValue: _dir, onChanged: (v){ if(v!=null)setState(()=>_dir=v); }),
          const Divider(),
          SwitchListTile(title: const Text('下载文件超过12小时后自动删除'), value: _auto, onChanged: (v)=>setState(()=>_auto=v)),
          const Divider(),
          SwitchListTile(title: const Text('禁止截图/录屏（FLAG_SECURE）'), value: _sec, onChanged: (v)=>setState(()=>_sec=v)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}

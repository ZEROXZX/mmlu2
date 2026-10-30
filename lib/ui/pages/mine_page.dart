import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_store.dart';
import '../../core/network/auth_api.dart';
import 'downloads_page.dart';
import 'register_page.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});
  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  Map<String,dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final store = AuthStore(prefs);
    setState(() => _user = store.user);
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(context: context, builder: (c)=>AlertDialog(
      title: const Text('退出账号'),
      content: const Text('确定要退出登录吗？'),
      actions: [TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text('取消')), TextButton(onPressed: ()=>Navigator.pop(c,true), child: const Text('确定'))],
    ));
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    final store = AuthStore(prefs);
    await store.clear();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RegisterPage()), (r)=>false);
  }

  Future<void> _checkUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final store = AuthStore(prefs);
      final dio = Dio();
      if (store.token != null) dio.options.headers['Authorization'] = 'Bearer ${store.token}';
      final api = AuthApi(dio, 'http://127.0.0.1:8090');
      final c = await api.config();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('配置: ${c.toString()}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    return ListView(
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(u?['username']?.toString() ?? '未登录'),
          subtitle: Text(u?['email']?.toString() ?? ''),
        ),
        const Divider(),
        const ListTile(title: Text('功能')),
        ListTile(leading: const Icon(Icons.download), title: const Text('下载管理'), onTap: ()=>Navigator.of(context).push(MaterialPageRoute(builder: (_)=>const DownloadsPage()))),
        const Divider(),
        const ListTile(title: Text('系统')),
        ListTile(leading: const Icon(Icons.campaign), title: const Text('远程公告'), onTap: _checkUpdate),
        ListTile(leading: const Icon(Icons.system_update), title: const Text('检查更新'), onTap: _checkUpdate),
        ListTile(leading: const Icon(Icons.logout), title: const Text('退出账号'), onTap: _logout),
      ],
    );
  }
}

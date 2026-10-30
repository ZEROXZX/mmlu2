import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_store.dart';
import '../../core/auth/token_store.dart';
import '../../core/network/auth_api.dart';
import 'home_shell.dart';
import 'register_page.dart';
import 'account_banned_page.dart';
import 'package:dio/dio.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final newStore = AuthStore(prefs);
    final oldStore = TokenStore(prefs);

    // 原账号已登录，直接放行
    if (oldStore.isLoggedIn && oldStore.token != null && oldStore.token!.isNotEmpty) {
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
      return;
    }

    // 新自建账号登录校验
    if (!newStore.isLoggedIn) {
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RegisterPage()));
      return;
    }
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
    dio.options.headers['Authorization'] = 'Bearer ${newStore.token}';
    final api = AuthApi(dio, 'http://127.0.0.1:8090');
    try {
      final r = await api.me();
      final user = r['user'];
      await newStore.save(token: newStore.token!, user: Map<String,dynamic>.from(user), tv: user['token_version']);
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    } catch (e) {
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['code'] == 'ACCOUNT_BANNED') {
          if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => AccountBannedPage(msg: data['message']?.toString())), (r)=>false);
          return;
        }
      }
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RegisterPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

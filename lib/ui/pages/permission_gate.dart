import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/service/native_bridge.dart';

/// 启动授权闸门：打开 App 首先申请「存储 / 相册 / 通知」权限，
/// **未授权则无法进入 App**。授权成功后自动放行；点「去授权」会弹系统权限框
/// （Android 11+ 的「所有文件访问」会跳到系统设置页），返回后自动重新检测。
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key, required this.child});

  final Widget child;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  bool? _granted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首次进入就主动弹授权（非 Android 直接放行）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _request());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页返回后重新检测。
    if (state == AppLifecycleState.resumed && _granted != true) {
      unawaited(_detect());
    }
  }

  Future<void> _detect() async {
    if (!NativeBridge.isAndroid) {
      if (mounted) setState(() => _granted = true);
      return;
    }
    final ok = await NativeBridge.isStorageReady();
    if (mounted) setState(() => _granted = ok);
  }

  Future<void> _request() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await NativeBridge.ensurePermissions(requestManage: true);
    } catch (_) {}
    // 等系统权限页/设置页返回后再检测。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _check();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _check() async {
    if (!NativeBridge.isAndroid) {
      if (mounted) setState(() => _granted = true);
      return;
    }
    final ok = await NativeBridge.isStorageReady();
    if (mounted) setState(() => _granted = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == true) return widget.child;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_special,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              const Text('需要存储权限',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(
                '本应用需要「存储 / 相册 / 通知」权限，用于把下载内容保存到'
                '手机 Download / Pictures 目录并通知下载完成。\n'
                '未授权将无法使用本应用。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 24),
              if (_granted == null)
                const CircularProgressIndicator()
              else
                FilledButton.icon(
                  onPressed: _busy ? null : _request,
                  icon: const Icon(Icons.verified_user),
                  label: Text(_busy ? '正在请求…' : '去授权'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _check,
                child: const Text('已授权？重新检测'),
              ),
              const SizedBox(height: 4),
              Text(
                'Android 11+ 需在系统设置里开启「所有文件访问权限」。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

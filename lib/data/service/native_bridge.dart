import 'dart:io';

import 'package:flutter/services.dart';

/// 原生能力桥（Android）：运行时权限 / 公共目录 / 媒体扫描(入相册) / 下载完成通知。
///
/// 非 Android 平台，或原生调用失败时**安全降级**（返回 null / false），
/// 绝不让下载主流程因权限/原生异常而崩溃。
class NativeBridge {
  NativeBridge._();

  static const MethodChannel _ch = MethodChannel('mmlu/native');

  static bool get _isAndroid => Platform.isAndroid;

  /// 请求权限（存储 / 相册 / 通知）。
  /// Android 11+ 若缺"所有文件访问"，[requestManage] 为真时会跳转系统设置页。
  /// 返回是否已具备写入公共目录的能力。
  static Future<bool> ensurePermissions({bool requestManage = true}) async {
    if (!_isAndroid) return false;
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>(
        'ensurePermissions',
        {'requestManage': requestManage},
      );
      return r?['storage'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 当前是否已具备写入公共目录的能力。
  static Future<bool> isStorageReady() async {
    if (!_isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('isStorageReady') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 公共目录绝对路径，如 type=`Download`、relative=`mmlu`
  /// → `/storage/emulated/0/Download/mmlu`。不可用时返回 null。
  static Future<String?> publicDir(String type, String relative) async {
    if (!_isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>(
        'publicDir',
        {'type': type, 'relative': relative},
      );
    } catch (_) {
      return null;
    }
  }

  /// 通知系统媒体库扫描文件，使其出现在相册/图库中。
  static Future<void> scanMedia(String path) async {
    if (!_isAndroid) return;
    try {
      await _ch.invokeMethod('scanMedia', {'path': path});
    } catch (_) {}
  }

  /// 发送系统通知（下载完成）。
  static Future<void> notify({
    required int id,
    required String title,
    String body = '',
  }) async {
    if (!_isAndroid) return;
    try {
      await _ch.invokeMethod('notify', {'id': id, 'title': title, 'body': body});
    } catch (_) {}
  }
}

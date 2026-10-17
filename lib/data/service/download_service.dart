import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'native_bridge.dart';

/// FFmpeg 转码封装（使用 ffmpeg_kit_flutter_new）。
class Mp4Converter {
  const Mp4Converter();

  /// 将 TS 合并为 MP4。`-c copy` 直接封装（无需重编码）；失败则回退重编码。
  Future<bool> tsToMp4(String tsPath, String mp4Path) async {
    try {
      final r = await FFmpegKit.execute(
          '-y -i "$tsPath" -c copy -bsf:a aac_adtstoasc "$mp4Path"');
      final rc = await r.getReturnCode();
      if (rc != null && ReturnCode.isSuccess(rc)) {
        if (File(mp4Path).existsSync()) return true;
      }
      final r2 = await FFmpegKit.execute('-y -i "$tsPath" "$mp4Path"');
      final rc2 = await r2.getReturnCode();
      return (rc2 != null && ReturnCode.isSuccess(rc2)) &&
          File(mp4Path).existsSync();
    } catch (_) {
      return false;
    }
  }
}

/// 下载底层工具：产物目录、FFmpeg 转码、明文拉取、删除。
///
/// 任务编排（进度/暂停/恢复/取消/并发）在 `DownloadManager`；
/// 这里只提供无状态的原子能力。
class DownloadService {
  DownloadService({Mp4Converter? converter, Future<Directory> Function()? rootOverride})
      : converter = converter ?? const Mp4Converter(),
        _rootOverride = rootOverride;

  final Mp4Converter converter;
  final Future<Directory> Function()? _rootOverride;

  /// 下载根目录。
  ///
  /// - Android：公共 `Download/mmlu`（需存储权限；`publicDir` 不可用时回退 app 私有目录）
  /// - 其他平台 / 测试：[rootOverride] 注入目录下的 `mmlu_downloads`，
  ///   否则 `<docs>/mmlu_downloads`。
  Future<Directory> rootDir() async {
    final override = _rootOverride;
    if (override != null) {
      final base = await override();
      return _ensure(Directory(p.join(base.path, 'mmlu_downloads')));
    }
    if (Platform.isAndroid) {
      final pub = await NativeBridge.publicDir('Download', 'mmlu');
      if (pub != null) return _ensure(Directory(pub));
    }
    final base = await getApplicationDocumentsDirectory();
    return _ensure(Directory(p.join(base.path, 'mmlu_downloads')));
  }

  /// 分类子目录 `Download/mmlu/<name>`（如 动画 / 漫画 / 小说 / 图集）。
  Future<Directory> subDir(String name) async {
    final root = await rootDir();
    return _ensure(Directory(p.join(root.path, name)));
  }

  /// 相册输出目录 `Pictures/mmlu/<name>`；非 Android 或不可用时返回 null。
  Future<Directory?> galleryDir(String name) async {
    if (!Platform.isAndroid) return null;
    final pub = await NativeBridge.publicDir('Pictures', p.join('mmlu', name));
    if (pub == null) return null;
    return _ensure(Directory(pub));
  }

  /// 让文件进入系统媒体库（相册/视频库）。
  Future<void> scanMedia(String path) => NativeBridge.scanMedia(path);

  Directory _ensure(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> deleteLocal(String filePath) async {
    try {
      final f = File(filePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

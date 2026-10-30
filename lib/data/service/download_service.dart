import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'native_bridge.dart';
import '../../core/auth/token_store.dart';

/// FFmpeg 转码封装。
///
/// 在 Android 上优先使用随包附带的 `/data/data/<pkg>/files/ffmpeg`（此处由应用复制）；
/// 也可传入 [ffmpegPath] 指定路径。
class Mp4Converter {
  Mp4Converter({this.ffmpegPath = 'ffmpeg'});

  final String ffmpegPath;

  /// 将 TS 合并为 MP4。`-c copy` 直接封装（无需重编码）；失败则回退重编码。
  Future<bool> tsToMp4(String tsPath, String mp4Path) async {
    try {
      // Try multiple common locations and commands (bundle jniLibs -> lib/..., or system)
      final candidates = <String>[
        '/data/data/com.zero.mmlu/files/ffmpeg',
        ffmpegPath,
        'ffmpeg',
        '/system/bin/ffmpeg',
      ];
      for (final exe in candidates) {
        try {
          final r = await Process.run(exe, [
            '-y',
            '-i', tsPath,
            '-c', 'copy',
            '-bsf:a', 'aac_adtstoasc',
            '-movflags', '+faststart',
            mp4Path,
          ]);
          if (r.exitCode == 0 && File(mp4Path).existsSync()) return true;
          final r2 = await Process.run(exe, [
            '-y',
            '-i', tsPath,
            '-avoid_negative_ts', 'make_zero',
            '-map', '0:v:0',
            '-map', '0:a:0?',
            '-c:v', 'libx264',
            '-c:a', 'aac',
            '-preset', 'veryfast',
            '-movflags', '+faststart',
            mp4Path,
          ]);
          if (r2.exitCode == 0 && File(mp4Path).existsSync()) return true;
        } catch (_) {}
      }
      return false;
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
      : converter = converter ?? Mp4Converter(),
        _rootOverride = rootOverride;

  final Mp4Converter converter;
  final Future<Directory> Function()? _rootOverride;

  /// 下载根目录。
  Future<Directory> rootDir({TokenStore? tokenStore}) async {
    // always read latest
    TokenStore? ts = tokenStore;
    if (ts == null) {
      try {
        // try to get from container not available; but keep
      } catch (_) {}
    }
    final override = _rootOverride;
    if (override != null) {
      final base = await override();
      return _ensure(Directory(p.join(base.path, 'mmlu_downloads')));
    }
    if (Platform.isAndroid) {
      String dir = 'root_app';
      if (ts != null) {
        dir = await ts.getDownloadDir();
      } else if (tokenStore != null) {
        dir = await tokenStore.getDownloadDir();
      }
      if (dir == 'download') {
        final pub = await NativeBridge.publicDir('Download', 'mmlu');
        if (pub != null) return _ensure(Directory(pub));
        // fallback
        final d = Directory('/storage/emulated/0/Download/mmlu');
        try {
          if (!d.existsSync()) d.createSync(recursive: true);
          return d;
        } catch (_) {}
      } else {
        final candidates = [
          '/data/user/0/com.zero.mmlu',
          '/data/data/com.zero.mmlu',
        ];
        for (final c in candidates) {
          final d1 = Directory(p.join(c, 'mmlu'));
          try {
            if (!d1.existsSync()) d1.createSync(recursive: true);
            return d1;
          } catch (_) {}
        }
      }
      final pub = await NativeBridge.publicDir('Download', 'mmlu');
      if (pub != null) return _ensure(Directory(pub));
    }
    final base = await getApplicationDocumentsDirectory();
    return _ensure(Directory(p.join(base.path, 'mmlu_downloads')));
  }

  /// 分类子目录
  Future<Directory> subDir(String name, {TokenStore? tokenStore}) async {
    final root = await rootDir(tokenStore: tokenStore);
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

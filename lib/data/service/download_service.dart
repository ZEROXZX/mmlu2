import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// FFmpeg 转码封装。
///
/// 默认调用系统/内置 `ffmpeg` 可执行文件（Android 可随包附带 ffmpeg 二进制，
/// 或替换为 ffmpeg_kit 插件）。可用 [ffmpegPath] 指定路径。
class Mp4Converter {
  Mp4Converter({this.ffmpegPath = 'ffmpeg'});

  final String ffmpegPath;

  /// 将 TS 合并为 MP4。`-c copy` 直接封装（无需重编码）。
  Future<bool> tsToMp4(String tsPath, String mp4Path) async {
    try {
      final r = await Process.run(ffmpegPath, [
        '-y',
        '-i', tsPath,
        '-c', 'copy',
        '-bsf:a', 'aac_adtstoasc',
        mp4Path,
      ]);
      if (r.exitCode == 0 && File(mp4Path).existsSync()) return true;
      // 退化：重编码
      final r2 = await Process.run(ffmpegPath, [
        '-y', '-i', tsPath, mp4Path,
      ]);
      return r2.exitCode == 0 && File(mp4Path).existsSync();
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

  /// 下载根目录 `<docs>/mmlu_downloads`（测试可注入 [rootOverride]）。
  Future<Directory> rootDir() async {
    final base = await (_rootOverride?.call() ?? getApplicationDocumentsDirectory());
    final dir = Directory(p.join(base.path, 'mmlu_downloads'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 拉取明文 UTF-8 文本（小说章节；带重试）。
  Future<String> getText(String url, {int tries = 8}) async {
    Object? last;
    for (var i = 0; i < tries; i++) {
      try {
        final r = await Dio().get<List<int>>(url,
            options: Options(
              responseType: ResponseType.bytes,
              headers: {'User-Agent': 'okhttp/4.9.0'},
            ));
        final b = r.data;
        if (b != null && b.isNotEmpty) return utf8.decode(b, allowMalformed: true);
        last = StateError('empty: $url');
      } catch (e) {
        last = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 500 + i * 400));
    }
    throw StateError('拉取失败: $url ($last)');
  }

  Future<void> deleteLocal(String filePath) async {
    try {
      final f = File(filePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

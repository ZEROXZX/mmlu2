import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../../data/service/download_store.dart';

/// 播放页。
///
/// HLS m3u8 经服务端加密，系统播放器无法直读；故采用「先下载解密落盘 → 本地播放」
/// 的方式（与 R1.5 内置 FFmpeg 转 MP4 一致）。若已有本地成品则直接播放。
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.item,
    required this.mediaPath,
    required this.quality,
    this.episodes = const [],
  });

  final ContentItem item;
  final String mediaPath;
  final String quality;
  final List<ContentItem> episodes;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  DownloadRecord? _existing;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppContainer>().downloadStore;
    final id = '${widget.item.kind.tag}_${widget.item.id}_${widget.quality}';
    final found = store.load().where((r) => r.id == id && r.status == 'done').toList();
    if (found.isNotEmpty) {
      _existing = found.first;
      _openFile(_existing!.filePath);
    }
  }

  Future<void> _openFile(String path) async {
    final f = File(path);
    if (!f.existsSync()) {
      setState(() => _status = '本地文件不存在，请重新下载');
      return;
    }
    final c = VideoPlayerController.file(f);
    await c.initialize();
    if (!mounted) return;
    setState(() {
      _controller = c;
      _status = null;
    });
    c.play();
  }

  Future<void> _downloadAndPlay() async {
    final container = context.read<AppContainer>();
    setState(() {
      _busy = true;
      _status = '已加入下载队列…';
    });
    try {
      container.downloadManager.addVideo(
        item: widget.item,
        mediaPath: widget.mediaPath,
        quality: widget.quality,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入下载队列，可在「下载」页查看进度')));
      }
    } catch (e) {
      setState(() => _status = '失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.item.title} · ${widget.quality}')),
      backgroundColor: Colors.black,
      body: Center(
        child: ctrl != null && ctrl.value.isInitialized
            ? AspectRatio(
                aspectRatio: ctrl.value.aspectRatio == 0 ? 16 / 9 : ctrl.value.aspectRatio,
                child: VideoPlayer(ctrl),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.ondemand_video, color: Colors.white54, size: 64),
                  const SizedBox(height: 16),
                  Text(_status ?? '尚未下载，点击下方开始下载并播放',
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _downloadAndPlay,
                    icon: const Icon(Icons.download),
                    label: const Text('下载并播放'),
                  ),
                ],
              ),
      ),
      floatingActionButton: ctrl != null && ctrl.value.isInitialized
          ? FloatingActionButton(
              onPressed: () => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play(),
              child: Icon(ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )
          : null,
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../../data/service/download_service.dart';

class EpisodeItem {
  const EpisodeItem({
    required this.id,
    required this.title,
    required this.qualities,
  });

  final String id;
  final String title;
  final List<String> qualities;
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.kind,
    required this.episodes,
    this.initialIndex = 0,
    this.initialQuality,
  });

  final ContentKind kind;
  final List<EpisodeItem> episodes;
  final int initialIndex;
  final String? initialQuality;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late int _curIdx;
  late EpisodeItem _curItem;
  late String _curQuality;
  VideoPlayerController? _controller;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _fullscreen = false;
  bool _busy = false;
  double _playbackSpeed = 1.0;
  bool _isSeeking = false;
  bool _wasPlayingBeforeSeek = false;

  @override
  void initState() {
    super.initState();
    _curIdx = widget.initialIndex;
    _curItem = widget.episodes[_curIdx];
    _curQuality = widget.initialQuality ?? _curItem.qualities.first;
    _load();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  Future<void> _swap(VideoPlayerController next) async {
    final old = _controller;
    final pos = old?.value.position ?? Duration.zero;
    await old?.pause();
    setState(() {
      _controller = next;
      _busy = true;
    });
    try {
      await next.initialize();
      await next.setPlaybackSpeed(_playbackSpeed);
      await next.seekTo(pos);
      await next.play();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await old?.dispose();
  }

  Future<void> _load() async {
    final c = context.read<AppContainer>();
    setState(() => _busy = true);
    try {
      final localPath = await c.downloadService.getLocalFile(
        widget.kind,
        _curItem.id,
        _curQuality,
      );
      if (localPath != null) {
        final f = File(localPath);
        if (await f.exists()) {
          final ctrl = VideoPlayerController.file(f);
          await _swap(ctrl);
          return;
        }
      }

      final url = await c.contentRepo.getMediaUrl(
        widget.kind,
        _curItem.id,
        _curQuality,
      );
      if (url == null || url.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('播放地址解析失败')),
          );
        }
        return;
      }

      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await _swap(ctrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _togglePlay() {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    setState(() {});
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _resetHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
  }

  Future<void> _showEpisodes() async {
    final idx = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: widget.episodes.length,
        itemBuilder: (ctx, i) {
          final ep = widget.episodes[i];
          return ListTile(
            title: Text(ep.title),
            selected: i == _curIdx,
            onTap: () => Navigator.pop(ctx, i),
          );
        },
      ),
    );
    if (idx != null && idx != _curIdx) {
      setState(() {
        _curIdx = idx;
        _curItem = widget.episodes[_curIdx];
        _curQuality = _curItem.qualities.first;
      });
      await _load();
    }
  }

  Future<void> _enqueueOffline() async {
    final c = context.read<AppContainer>();
    await c.downloadService.enqueue(
      DownloadTask(
        id: _curItem.id,
        title: _curItem.title,
        kind: widget.kind,
        quality: _curQuality,
        type: DownloadType.video,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加入下载队列')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final ready = ctrl != null && ctrl.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: GestureDetector(
                onTap: _toggleControls,
                onDoubleTap: _togglePlay,
                onHorizontalDragUpdate: (details) {
                  if (_controller == null || !_controller!.value.isInitialized) return;
                  final delta = details.delta.dx / context.size!.width;
                  final duration = _controller!.value.duration;
                  final position = _controller!.value.position;
                  final newPosition = position + Duration(
                    milliseconds: (delta * duration.inMilliseconds * 0.1).round(),
                  );
                  final clamped = newPosition.clamp(Duration.zero, duration) as Duration;
                  _controller!.seekTo(clamped);
                },
                child: ready
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: ctrl.value.aspectRatio == 0
                              ? 16 / 9
                              : ctrl.value.aspectRatio,
                          child: VideoPlayer(ctrl),
                        ),
                      )
                    : _placeholder(context),
              ),
            ),
            if (ready && ctrl.value.isBuffering)
              const Positioned.fill(
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_busy)
              const Positioned.fill(
                child: Center(child: CircularProgressIndicator()),
              ),
            if (ready && _showControls) ..._buildOverlay(context, ctrl),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.play_circle_outline, size: 80, color: Colors.white54),
        const SizedBox(height: 16),
        Text(
          _curItem.title,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
  List<Widget> _buildOverlay(BuildContext context, VideoPlayerController ctrl) {
    final scheme = Theme.of(context).colorScheme;
    return [
      // 顶部控制栏
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black54, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  '${_curItem.title} · $_curQuality',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              if (widget.episodes.length > 1)
                IconButton(
                  tooltip: '合集',
                  icon: const Icon(Icons.queue_music, color: Colors.white),
                  onPressed: _showEpisodes,
                ),
              IconButton(
                tooltip: '下载离线',
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: _enqueueOffline,
              ),
              IconButton(
                tooltip: _fullscreen ? '退出全屏' : '全屏',
                icon: Icon(
                  _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                ),
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ),
      ),
      // 中央播放/暂停按钮
      Positioned.fill(
        child: Center(
          child: GestureDetector(
            onTap: _togglePlay,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: Icon(
                ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                size: 48,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
      // 底部控制栏
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 自定义进度条
              GestureDetector(
                onHorizontalDragStart: (details) {
                  if (!_isSeeking) {
                    setState(() {
                      _isSeeking = true;
                      _wasPlayingBeforeSeek = ctrl.value.isPlaying;
                    });
                  }
                },
                onHorizontalDragUpdate: (details) {
                  if (_isSeeking && ctrl.value.isInitialized) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final tapPosition = details.localPosition.dx;
                      final totalWidth = box.size.width;
                      final ratio = (tapPosition / totalWidth).clamp(0.0, 1.0);
                      final newPosition = ctrl.value.duration * ratio;
                      ctrl.seekTo(newPosition);
                    }
                  }
                },
                onHorizontalDragEnd: (details) {
                  if (_isSeeking) {
                    setState(() => _isSeeking = false);
                    if (_wasPlayingBeforeSeek) {
                      ctrl.play();
                    }
                  }
                },
                child: Container(
                  height: 20,
                  color: Colors.transparent,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // 缓冲进度
                      if (ctrl.value.buffered.isNotEmpty)
                        FractionallySizedBox(
                          widthFactor: ctrl.value.buffered.last.end.inMilliseconds /
                              ctrl.value.duration.inMilliseconds,
                          child: Container(
                            height: 4,
                            color: Colors.white30,
                          ),
                        ),
                      // 播放进度
                      FractionallySizedBox(
                        widthFactor: ctrl.value.position.inMilliseconds /
                            ctrl.value.duration.inMilliseconds,
                        child: Container(
                          height: 4,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: _togglePlay,
                  ),
                  Text(
                    _fmt(ctrl.value.position),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const Spacer(),
                  // 倍速选择按钮
                  PopupMenuButton<double>(
                    initialValue: _playbackSpeed,
                    onSelected: (speed) async {
                      setState(() => _playbackSpeed = speed);
                      await ctrl.setPlaybackSpeed(speed);
                    },
                    itemBuilder: (context) => [
                      for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                        PopupMenuItem(
                          value: speed,
                          child: Text('${speed}x'),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white54),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_playbackSpeed}x',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fmt(ctrl.value.duration),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  IconButton(
                    icon: Icon(
                      _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                    ),
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}

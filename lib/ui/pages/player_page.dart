import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../../data/service/download_task.dart';

/// 播放页：直流播放（本地代理）优先，无本地成品时也直接播。
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
  String? _status;
  bool _busy = false;
  bool _showControls = true;
  bool _fullscreen = false;
  Timer? _hideTimer;
  double _speed = 1.0;
  Offset? _dragStart;
  double _dragDx = 0;
  Duration _seekPreview = Duration.zero;

  late ContentItem _curItem;
  late String _curMedia;
  late String _curQuality;

  @override
  void initState() {
    super.initState();
    _curItem = widget.item;
    _curMedia = widget.mediaPath;
    _curQuality = widget.quality;
    _boot();
  }

  Future<void> _boot() async {
    final store = context.read<AppContainer>().downloadStore;
    final id = '${_curItem.kind.tag}_${_curItem.id}_$_curQuality';
    final found = store.load().where((r) => r.id == id && r.status == 'done').toList();
    if (found.isNotEmpty && File(found.first.filePath).existsSync()) {
      await _openFile(found.first.filePath);
    } else {
      await _startStream();
    }
  }

  Future<void> _swap(VideoPlayerController next) async {
    final old = _controller;
    _controller = next;
    if (old != null) {
      old.removeListener(_onTick);
      await old.dispose();
    }
    next.addListener(_onTick);
  }

  Future<void> _openFile(String path) async {
    final f = File(path);
    if (!f.existsSync()) {
      await _startStream();
      return;
    }
    final c = VideoPlayerController.file(f);
    try {
      await c.initialize();
    } catch (e) {
      if (mounted) setState(() => _status = '本地文件打开失败：$e');
      await c.dispose();
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    await _swap(c);
    setState(() {
      _status = null;
      _busy = false;
    });
    c.play();
    _scheduleHide();
  }

  Future<void> _startStream() async {
    setState(() {
      _busy = true;
      _status = '连接中…';
    });
    try {
      final url = await context.read<AppContainer>().hlsProxy.playUrl(_curMedia);
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await c.initialize();
      } catch (e) {
        await c.dispose();
        rethrow;
      }
      if (!mounted) {
        await c.dispose();
        return;
      }
      await _swap(c);
      setState(() {
        _status = null;
        _busy = false;
      });
      c.play();
      _scheduleHide();
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '播放失败：$e';
          _busy = false;
        });
      }
    }
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_controller?.value.isPlaying == true && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
      setState(() => _showControls = true);
      _hideTimer?.cancel();
    } else {
      c.play();
      _scheduleHide();
    }
    setState(() {});
  }

  void _toggleFullscreen() {
    _fullscreen = !_fullscreen;
    if (_fullscreen) {
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    setState(() {});
  }

  Future<void> _enqueueOffline() async {
    final mgr = context.read<DownloadManager>();
    mgr.addVideo(item: _curItem, mediaPath: _curMedia, quality: _curQuality);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入下载队列，可在「下载」页查看进度')));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      c.dispose();
    }
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleControls,
                child: ready
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: ctrl.value.aspectRatio == 0 ? 16 / 9 : ctrl.value.aspectRatio,
                          child: VideoPlayer(ctrl),
                        ),
                      )
                    : _placeholder(),
              ),
            ),
            if (ready && ctrl.value.isBuffering)
              const Positioned.fill(child: Center(child: CircularProgressIndicator())),
            if (_busy)
              const Positioned.fill(child: Center(child: CircularProgressIndicator())),
            if (ready && _showControls) ..._overlay(ctrl),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.ondemand_video, color: Colors.white54, size: 64),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(_status ?? '正在准备播放…', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ),
        const SizedBox(height: 16),
        if (_status != null && !_busy)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(onPressed: _startStream, icon: const Icon(Icons.refresh), label: const Text('重试')),
              const SizedBox(width: 12),
              FilledButton.icon(onPressed: _enqueueOffline, icon: const Icon(Icons.download), label: const Text('下载离线')),
            ],
          ),
      ],
    );
  }

  List<Widget> _overlay(VideoPlayerController ctrl) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent])),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.of(context).maybePop()),
              Expanded(child: Text('${_curItem.title} · $_curQuality', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
              PopupMenuButton<double>(
                tooltip: '播放倍速',
                icon: const Text('倍速', style: TextStyle(color: Colors.white, fontSize: 12)),
                initialValue: _speed,
                onSelected: (v) async {
                  setState(() => _speed = v);
                  try {
                    await _controller?.setPlaybackSpeed(v);
                  } catch (_) {}
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 0.5, child: Text('0.5x')),
                  PopupMenuItem(value: 0.75, child: Text('0.75x')),
                  PopupMenuItem(value: 1.0, child: Text('1.0x')),
                  PopupMenuItem(value: 1.25, child: Text('1.25x')),
                  PopupMenuItem(value: 1.5, child: Text('1.5x')),
                  PopupMenuItem(value: 1.75, child: Text('1.75x')),
                  PopupMenuItem(value: 2.0, child: Text('2.0x')),
                ],
              ),
              IconButton(tooltip: '下载离线', icon: const Icon(Icons.download, color: Colors.white), onPressed: _enqueueOffline),
              IconButton(tooltip: _fullscreen ? '退出全屏' : '全屏', icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white), onPressed: _toggleFullscreen),
            ],
          ),
        ),
      ),
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          onHorizontalDragStart: (d) {
            _dragStart = d.globalPosition;
            _dragDx = 0;
            _seekPreview = ctrl.value.position;
            setState(() {});
          },
          onHorizontalDragUpdate: (d) {
            if (_dragStart == null) return;
            _dragDx += d.delta.dx;
            final width = MediaQuery.of(context).size.width;
            if (width <= 0) return;
            final total = ctrl.value.duration.inSeconds > 0 ? ctrl.value.duration : const Duration(minutes: 10);
            final sec = (_dragDx / width * 90).round();
            var np = ctrl.value.position + Duration(seconds: sec);
            if (np < Duration.zero) np = Duration.zero;
            if (np > total) np = total;
            setState(() => _seekPreview = np);
          },
          onHorizontalDragEnd: (d) async {
            if (_dragStart == null) return;
            try {
              await ctrl.seekTo(_seekPreview);
            } catch (_) {}
            _dragStart = null;
            _dragDx = 0;
            setState(() {});
          },
          child: Stack(
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: Icon(ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow, size: 48, color: Colors.white),
                ),
              ),
              if (_dragStart != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                    child: Text('${_fmt(_seekPreview)} / ${_fmt(ctrl.value.duration)}', style: const TextStyle(color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
          padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressIndicator(ctrl, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 4), colors: VideoProgressColors(playedColor: scheme.primary, bufferedColor: Colors.white30, backgroundColor: Colors.white12)),
              Row(
                children: [
                  IconButton(icon: Icon(ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white), onPressed: _togglePlay),
                  Text(_fmt(ctrl.value.position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const Spacer(),
                  Text(_fmt(ctrl.value.duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  IconButton(icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white), onPressed: _toggleFullscreen),
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

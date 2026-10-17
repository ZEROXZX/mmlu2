import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../../data/service/download_task.dart';

/// 播放页。
///
/// - 默认**直流播放**：经 [HlsProxy] 本地代理把加密 HLS 转成明文流，
///   `networkUrl(127.0.0.1)` 边下边播，不必等整集下载完；
/// - 若本地已有下载成品（done 记录）则直接播本地文件（离线优先）；
/// - 「下载离线」入口：入队 [DownloadManager]，可后台暂停/取消，
///   完成后自动切换为本地播放。
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

  /// R4.1 合集：同作品分集（已按 season→ep 排序），播放中可直接切换。
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
  VoidCallback? _managerListener;
  String? _watchTaskId;

  /// 当前播放的分集 / 画质（合集切换时更新，非 final）。
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
    final found =
        store.load().where((r) => r.id == id && r.status == 'done').toList();
    if (found.isNotEmpty && File(found.first.filePath).existsSync()) {
      await _openFile(found.first.filePath);
    } else {
      // 无本地成品（或文件已丢）→ 直接边下边播。
      await _startStream();
    }
  }

  // ---- 控制器生命周期 -------------------------------------------------------

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
      // 文件播放过程中被删/移动 → 回退到流播。
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
      final url = await context
          .read<AppContainer>()
          .hlsProxy
          .playUrl(_curMedia);
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
    final v = _controller?.value;
    if (v == null) return;
    if (!v.isPlaying) _hideTimer?.cancel();
    setState(() {});
  }

  // ---- 控制条显隐 -----------------------------------------------------------

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
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    setState(() {});
  }

  // ---- 下载离线（入队 + 完成后自动切本地） ---------------------------------

  Future<void> _enqueueOffline() async {
    final mgr = context.read<DownloadManager>();
    final id = mgr.addVideo(
      item: _curItem,
      mediaPath: _curMedia,
      quality: _curQuality,
    );
    _watchTaskId = id;
    if (_managerListener == null) {
      _managerListener = _checkWatched;
      mgr.addListener(_managerListener!);
    }
    _toast('已加入下载队列，可在「下载」页暂停/取消');
    _checkWatched();
  }

  void _checkWatched() {
    final id = _watchTaskId;
    if (id == null || !mounted) return;
    final mgr = context.read<DownloadManager>();
    final t = mgr.byId(id);
    if (t == null) return;
    if (t.status == DownloadStatus.done && t.outputPath != null) {
      _unwatch();
      _openFile(t.outputPath!);
    } else if (t.status == DownloadStatus.failed) {
      _unwatch();
      _toast('下载失败：${t.error ?? ''}');
    }
  }

  void _unwatch() {
    final l = _managerListener;
    if (l != null) {
      try {
        context.read<DownloadManager>().removeListener(l);
      } catch (_) {}
    }
    _managerListener = null;
    _watchTaskId = null;
  }

  // ---- 合集切换（R4.1） -----------------------------------------------------

  void _showEpisodes() {
    final list = [...widget.episodes]..sort((a, b) {
        final s = (a.season ?? 0).compareTo(b.season ?? 0);
        return s != 0 ? s : (a.ep ?? 0).compareTo(b.ep ?? 0);
      });
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '合集',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            for (final e in list)
              ListTile(
                selected: e.id == _curItem.id,
                selectedTileColor: Colors.white12,
                title: Text(
                  e.title.isEmpty ? (e.avkey ?? '第 ${e.ep} 集') : e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${e.season != null ? '第${e.season}季 ' : ''}第${e.ep ?? '-'}集',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: e.id == _curItem.id
                    ? const Icon(Icons.play_circle, color: Colors.white70)
                    : null,
                onTap: () => _switchEpisode(e),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchEpisode(ContentItem e) async {
    Navigator.of(context).maybePop();
    if (e.id == _curItem.id) return;
    final media = e.media;
    if (media.isEmpty) {
      _toast('该分集无播放源');
      return;
    }
    var q = _curQuality;
    if (!media.containsKey(q)) {
      final picked = await _pickQualityLocal(media.keys.toList());
      if (picked == null) return;
      q = picked;
    }
    if (!mounted) return;
    _unwatch();
    _hideTimer?.cancel();
    final old = _controller;
    _controller = null;
    if (old != null) {
      old.removeListener(_onTick);
      await old.dispose();
    }
    setState(() {
      _curItem = e;
      _curMedia = media[q]!;
      _curQuality = q;
      _busy = true;
      _status = '切换中…';
      _showControls = true;
    });
    await _boot();
  }

  Future<String?> _pickQualityLocal(List<String> qualities) {
    const order = ['720', '240', 'intro'];
    final sorted = qualities.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });
    return showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('该分集可用画质'),
        children: [
          for (final q in sorted)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, q),
              child: Text(q == '720'
                  ? '720P（默认最高）'
                  : q == '240'
                      ? '240P'
                      : q == 'intro'
                          ? '预告片'
                          : q),
            ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _unwatch();
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      c.dispose();
    }
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---- UI -------------------------------------------------------------------

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
            if (ready && _showControls) ..._overlay(context, ctrl),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.ondemand_video, color: Colors.white54, size: 64),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _status ?? '正在准备播放…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        const SizedBox(height: 16),
        if (_status != null && !_busy)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _startStream,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _enqueueOffline,
                icon: const Icon(Icons.download),
                label: const Text('下载离线'),
              ),
            ],
          ),
      ],
    );
  }

  List<Widget> _overlay(BuildContext context, VideoPlayerController ctrl) {
    final scheme = Theme.of(context).colorScheme;
    return [
      // 顶部：返回 / 标题 / 下载离线 / 全屏
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
                  _fullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  color: Colors.white,
                ),
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ),
      ),
      // 中央播放/暂停
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
      // 底部：进度条 + 时间
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
              VideoProgressIndicator(
                ctrl,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                colors: VideoProgressColors(
                  playedColor: scheme.primary,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white12,
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

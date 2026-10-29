import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../../data/service/resource_service.dart';
import '../widgets/async_view.dart';

/// 阅读器：漫画/图集为图片翻页；小说为文本滚动。
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.kind,
    required this.item,
    this.chapterId,
    this.fictionPath,
    this.title,
  });

  final ContentKind kind;
  final ContentItem item;
  final int? chapterId;
  final String? fictionPath;
  final String? title;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static final Map<String, Uint8List> _cache = {};

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? widget.item.title;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: widget.kind == ContentKind.fiction ? _buildFiction() : _buildImages(),
    );
  }

  // ---- 小说 ---------------------------------------------------------------

  Widget _buildFiction() {
    final container = context.read<AppContainer>();
    if (widget.fictionPath == null || widget.fictionPath!.isEmpty) {
      return const EmptyView(text: '无正文路径');
    }
    return AsyncView<String>(
      future: container.resourceService
          .getText(widget.kind, widget.fictionPath!),
      builder: (context, text) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(text, style: const TextStyle(fontSize: 17, height: 1.6)),
      ),
    );
  }

  // ---- 漫画 / 图集 --------------------------------------------------------

  Widget _buildImages() {
    final container = context.read<AppContainer>();
    return AsyncView<List<ReadPage>>(
      future: container.contentRepo.readPages(
        widget.kind,
        id: widget.item.id,
        chapterId: widget.chapterId,
      ),
      empty: const EmptyView(text: '无图片'),
      builder: (context, pages) => _PageViewer(
        kind: widget.kind,
        pages: pages,
        service: container.resourceService,
      ),
    );
  }
}

class _PageViewer extends StatefulWidget {
  const _PageViewer({required this.kind, required this.pages, required this.service});

  final ContentKind kind;
  final List<ReadPage> pages;
  final ResourceService service;

  @override
  State<_PageViewer> createState() => _PageViewerState();
}

class _PageViewerState extends State<_PageViewer> {
  final _controller = PageController();
  int _current = 1;
  bool _showBar = false;
  SharedPreferences? _prefs;

  ResourceRef _ref(ReadPage p) => ResourceRef(
        path: p.path,
        scheme: widget.kind == ContentKind.comicNs ? ImageScheme.nsComic : ImageScheme.perImage,
        key: p.key,
        iv: p.iv,
      );

  @override
  void initState() {
    super.initState();
    _loadBookmark();
  }

  Future<void> _loadBookmark() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs?.getInt('bookmark_page_${widget.kind.tag}');
    if (saved != null && saved >= 1 && saved <= widget.pages.length && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpToPage(saved - 1);
          setState(() => _current = saved);
        }
      });
    }
  }

  Future<void> _saveBookmark(int page) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setInt('bookmark_page_${widget.kind.tag}', page);
  }

  void _toggleBar() => setState(() => _showBar = !_showBar);

  Future<void> _jumpToPage() async {
    final ctrl = TextEditingController(text: _current.toString());
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到页码'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: '1-$pagesCount')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () {
            final v = int.tryParse(ctrl.text);
            Navigator.pop(ctx, v);
          }, child: const Text('跳转')),
        ],
      ),
    );
    if (res != null && res >= 1 && res <= widget.pages.length && _controller.hasClients) {
      _controller.jumpToPage(res - 1);
      setState(() => _current = res);
      _saveBookmark(res);
    }
  }

  int get pagesCount => widget.pages.length;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: _toggleBar,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.pages.length,
            onPageChanged: (i) {
              setState(() => _current = i + 1);
              _saveBookmark(i + 1);
            },
            itemBuilder: (context, i) => _PageImage(
              service: widget.service,
              kind: widget.kind,
              ref: _ref(widget.pages[i]),
            ),
          ),
        ),
        if (_showBar)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('$_current / ${widget.pages.length}', style: const TextStyle(color: Colors.white)),
                      const Spacer(),
                      TextButton.icon(onPressed: _jumpToPage, icon: const Icon(Icons.search, color: Colors.white), label: const Text('跳转', style: TextStyle(color: Colors.white))),
                      TextButton.icon(onPressed: () => _saveBookmark(_current), icon: const Icon(Icons.bookmark_add, color: Colors.white), label: const Text('书签', style: TextStyle(color: Colors.white))),
                    ],
                  ),
                  Slider(
                    value: _current.toDouble(),
                    min: 1,
                    max: widget.pages.length.toDouble(),
                    divisions: widget.pages.length > 1 ? widget.pages.length - 1 : 1,
                    onChanged: (v) {},
                    onChangeEnd: (v) {
                      final p = v.toInt();
                      if (_controller.hasClients) {
                        _controller.jumpToPage(p - 1);
                        setState(() => _current = p);
                        _saveBookmark(p);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        if (!_showBar)
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text('$_current / ${widget.pages.length}',
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
      ],
    );
  }
}

class _PageImage extends StatefulWidget {
  const _PageImage({required this.service, required this.kind, required this.ref});

  final ResourceService service;
  final ContentKind kind;
  final ResourceRef ref;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  late Future<Uint8List> _future = _load();

  Future<Uint8List> _load() async {
    final key = '${widget.kind.tag}:${widget.ref.path}';
    final cached = _ReaderPageState._cache[key];
    if (cached != null) return cached;
    final b = await widget.service.fetchDecrypted(widget.kind, widget.ref);
    if (b.isNotEmpty) {
      // 限制缓存规模，避免翻长漫时无上限增长。
      if (_ReaderPageState._cache.length > 400) {
        final toKeep = _ReaderPageState._cache.entries.take(200).toList();
        _ReaderPageState._cache.clear();
        for (final e in toKeep) {
          _ReaderPageState._cache[e.key] = e.value;
        }
      }
      _ReaderPageState._cache[key] = b;
    }
    return b;
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 4,
      child: Center(
        child: FutureBuilder<Uint8List>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final b = snap.data;
            if (snap.hasError || b == null || b.isEmpty) {
              return TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, color: Colors.grey),
                label: const Text('加载失败，点击重试',
                    style: TextStyle(color: Colors.grey)),
              );
            }
            return Image.memory(b, fit: BoxFit.contain);
          },
        ),
      ),
    );
  }
}

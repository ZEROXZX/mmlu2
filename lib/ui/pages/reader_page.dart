import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../../data/service/resource_service.dart';
import '../widgets/async_view.dart';

/// 阅读器：漫画/图集为图片横向翻页；小说为文本横向翻页（左右滑动）
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
      future: container.resourceService.getText(widget.kind, widget.fictionPath!),
      builder: (context, text) => _FictionViewer(
        text: text,
        kind: widget.kind,
        item: widget.item,
        chapterId: widget.chapterId,
        fictionPath: widget.fictionPath,
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

class _FictionViewer extends StatefulWidget {
  const _FictionViewer({required this.text, required this.kind, required this.item, this.chapterId, this.fictionPath});
  final String text;
  final ContentKind kind;
  final ContentItem item;
  final int? chapterId;
  final String? fictionPath;

  @override
  State<_FictionViewer> createState() => _FictionViewerState();
}

class _FictionViewerState extends State<_FictionViewer> {
  final _controller = PageController();
  int _current = 1;
  bool _showBar = false;
  SharedPreferences? _prefs;
  late List<String> _pages;

  String get _bmKey => 'fiction_bm_${widget.kind.tag}_${widget.item.id}_${widget.chapterId ?? widget.fictionPath.hashCode}';

  @override
  void initState() {
    super.initState();
    _split();
    _loadBookmark();
  }

  void _split() {
    const per = 850;
    if (widget.text.isEmpty) {
      _pages = [''];
    } else {
      _pages = [];
      for (var i = 0; i < widget.text.length; i += per) {
        final end = i + per > widget.text.length ? widget.text.length : i + per;
        _pages.add(widget.text.substring(i, end));
      }
    }
  }

  Future<void> _loadBookmark() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs?.getInt(_bmKey);
    if (saved != null && saved >= 1 && saved <= _pages.length && mounted) {
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
    await _prefs?.setInt(_bmKey, page);
  }

  Future<void> _addBookmark() async {
    _prefs ??= await SharedPreferences.getInstance();
    final list = List<String>.from(_prefs?.getStringList('fiction_bm_list') ?? []);
    final mark = 'f|${widget.item.id}|${widget.chapterId ?? 0}|${widget.fictionPath ?? ''}|$_current|${DateTime.now().millisecondsSinceEpoch}';
    // 避免完全重复（同本同章同页）
    list.removeWhere((e) {
      final p = e.split('|');
      if (p.length < 5) return false;
      return p[0]=='f' && p[1]==widget.item.id.toString() && p[2]==(widget.chapterId??0).toString() && p[4]==_current.toString();
    });
    list.add(mark);
    await _prefs?.setStringList('fiction_bm_list', list);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加书签')));
  }

  Future<void> _removeBookmark() async {
    _prefs ??= await SharedPreferences.getInstance();
    final list = List<String>.from(_prefs?.getStringList('fiction_bm_list') ?? []);
    list.removeWhere((e) {
      final p = e.split('|');
      if (p.length < 5) return false;
      return p[0]=='f' && p[1]==widget.item.id.toString() && p[2]==(widget.chapterId??0).toString() && p[4]==_current.toString();
    });
    await _prefs?.setStringList('fiction_bm_list', list);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除书签')));
  }

  void _toggleBar() => setState(() => _showBar = !_showBar);

  Future<void> _jumpToPage() async {
    final ctrl = TextEditingController(text: _current.toString());
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到页码'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: '1-${_pages.length}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () { final v = int.tryParse(ctrl.text); Navigator.pop(ctx, v); }, child: const Text('跳转')),
        ],
      ),
    );
    if (res != null && res >= 1 && res <= _pages.length && _controller.hasClients) {
      _controller.jumpToPage(res - 1);
      setState(() => _current = res);
      _saveBookmark(res);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: _toggleBar,
          child: PageView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: _pages.length,
            onPageChanged: (i) {
              setState(() => _current = i + 1);
              _saveBookmark(i + 1);
            },
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              child: SingleChildScrollView(
                child: SelectableText(_pages[i], style: const TextStyle(fontSize: 17, height: 1.7)),
              ),
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('$_current / ${_pages.length}', style: const TextStyle(color: Colors.white)),
                      const Spacer(),
                      TextButton.icon(onPressed: _jumpToPage, icon: const Icon(Icons.search, color: Colors.white), label: const Text('跳转', style: TextStyle(color: Colors.white))),
                      TextButton.icon(onPressed: _addBookmark, icon: const Icon(Icons.bookmark_add, color: Colors.white), label: const Text('添加书签', style: TextStyle(color: Colors.white))),
                      TextButton.icon(onPressed: _removeBookmark, icon: const Icon(Icons.bookmark_remove, color: Colors.white), label: const Text('删除书签', style: TextStyle(color: Colors.white))),
                    ],
                  ),
                  Slider(
                    value: _current.toDouble(),
                    min: 1,
                    max: _pages.length.toDouble(),
                    divisions: _pages.length > 1 ? _pages.length - 1 : 1,
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
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
              child: Text('$_current / ${_pages.length}', style: const TextStyle(color: Colors.white)),
            ),
          ),
      ],
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

  String get _bmKey => 'comic_bm_${widget.kind.tag}_${widget.pages.length}';

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
    final saved = _prefs?.getInt(_bmKey);
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
    await _prefs?.setInt(_bmKey, page);
  }

  Future<void> _addBookmark() async {
    _prefs ??= await SharedPreferences.getInstance();
    final list = List<String>.from(_prefs?.getStringList('comic_bm_list') ?? []);
    final mark = 'c|${widget.kind.tag}|${widget.pages.length}|$_current|${DateTime.now().millisecondsSinceEpoch}';
    list.removeWhere((e) {
      final p = e.split('|');
      if (p.length < 5) return false;
      return p[0]=='c' && p[1]==widget.kind.tag && p[3]==_current.toString();
    });
    list.add(mark);
    await _prefs?.setStringList('comic_bm_list', list);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加书签')));
  }

  Future<void> _removeBookmark() async {
    _prefs ??= await SharedPreferences.getInstance();
    final list = List<String>.from(_prefs?.getStringList('comic_bm_list') ?? []);
    list.removeWhere((e) {
      final p = e.split('|');
      if (p.length < 5) return false;
      return p[0]=='c' && p[1]==widget.kind.tag && p[3]==_current.toString();
    });
    await _prefs?.setStringList('comic_bm_list', list);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除书签')));
  }

  void _toggleBar() => setState(() => _showBar = !_showBar);

  Future<void> _jumpToPage() async {
    final ctrl = TextEditingController(text: _current.toString());
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到页码'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: '1-${widget.pages.length}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () { final v = int.tryParse(ctrl.text); Navigator.pop(ctx, v); }, child: const Text('跳转')),
        ],
      ),
    );
    if (res != null && res >= 1 && res <= widget.pages.length && _controller.hasClients) {
      _controller.jumpToPage(res - 1);
      setState(() => _current = res);
      _saveBookmark(res);
    }
  }

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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('$_current / ${widget.pages.length}', style: const TextStyle(color: Colors.white)),
                      const Spacer(),
                      TextButton.icon(onPressed: _jumpToPage, icon: const Icon(Icons.search, color: Colors.white), label: const Text('跳转', style: TextStyle(color: Colors.white))),
                      TextButton.icon(onPressed: _addBookmark, icon: const Icon(Icons.bookmark_add, color: Colors.white), label: const Text('添加书签', style: TextStyle(color: Colors.white))),
                      TextButton.icon(onPressed: _removeBookmark, icon: const Icon(Icons.bookmark_remove, color: Colors.white), label: const Text('删除书签', style: TextStyle(color: Colors.white))),
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
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
              child: Text('$_current / ${widget.pages.length}', style: const TextStyle(color: Colors.white)),
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
                label: const Text('加载失败，点击重试', style: TextStyle(color: Colors.grey)),
              );
            }
            return Image.memory(b, fit: BoxFit.contain);
          },
        ),
      ),
    );
  }
}

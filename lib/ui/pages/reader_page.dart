import 'dart:typed_data';

import 'package:flutter/material.dart';
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

  ResourceRef _ref(ReadPage p) => ResourceRef(
        path: p.path,
        scheme: widget.kind == ContentKind.comicNs ? ImageScheme.nsComic : ImageScheme.perImage,
        key: p.key,
        iv: p.iv,
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.pages.length,
          onPageChanged: (i) => setState(() => _current = i + 1),
          itemBuilder: (context, i) => _PageImage(
            service: widget.service,
            kind: widget.kind,
            ref: _ref(widget.pages[i]),
          ),
        ),
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

class _PageImage extends StatelessWidget {
  const _PageImage({required this.service, required this.kind, required this.ref});

  final ResourceService service;
  final ContentKind kind;
  final ResourceRef ref;

  @override
  Widget build(BuildContext context) {
    final key = '${kind.tag}:${ref.path}';
    final cached = _ReaderPageState._cache[key];
    final future = cached != null
        ? Future.value(cached)
        : service.fetchDecrypted(kind, ref).then((b) {
            _ReaderPageState._cache[key] = b;
            return b;
          });
    return InteractiveViewer(
      maxScale: 4,
      child: Center(
        child: FutureBuilder<Uint8List>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || snap.data == null) {
              return const Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40);
            }
            return Image.memory(snap.data!, fit: BoxFit.contain);
          },
        ),
      ),
    );
  }
}

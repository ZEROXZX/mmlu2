import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../widgets/async_view.dart';
import '../widgets/content_tile.dart';
import 'detail_page.dart';

enum ListSource { latest, ranking, recommend }

/// 内容列表页（最新 / 榜单 / 推荐 / 搜索）。
///
/// 支持**滚动到底自动加载下一页**（首页/分类的「更多」即进入本页）。
class ContentListPage extends StatefulWidget {
  const ContentListPage({
    super.key,
    required this.kind,
    this.source = ListSource.latest,
    this.title,
    this.keywords,
  });

  final ContentKind kind;
  final ListSource source;
  final String? title;

  /// 非空则走搜索。
  final String? keywords;

  @override
  State<ContentListPage> createState() => _ContentListPageState();
}

class _ContentListPageState extends State<ContentListPage> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  final _items = <ContentItem>[];
  final _seen = <String>{};

  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<List<ContentItem>> _loadPage(int page) {
    final repo = context.read<AppContainer>().contentRepo;
    if (widget.keywords != null) {
      return repo.search(widget.kind, widget.keywords!,
          pages: page, counts: _pageSize);
    }
    return switch (widget.source) {
      ListSource.latest =>
        repo.listNew(widget.kind, pages: page, counts: _pageSize),
      ListSource.ranking =>
        repo.listRanking(widget.kind, pages: page, counts: _pageSize),
      ListSource.recommend =>
        repo.listRecommend(widget.kind, pages: page, counts: _pageSize),
    };
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final next = _page + 1;
    try {
      final items = await _loadPage(next);
      if (!mounted) return;
      final before = _items.length;
      setState(() {
        _page = next;
        for (final it in items) {
          if (_seen.add('${it.kind.tag}:${it.id}:${it.source}')) _items.add(it);
        }
        // 无新增或本页不足一页 → 到底。
        _hasMore = items.length >= _pageSize && _items.length > before;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _title =>
      widget.title ?? '${widget.kind.label}·${_sourceLabel(widget.source)}';

  static String _sourceLabel(ListSource s) => switch (s) {
        ListSource.latest => '最新',
        ListSource.ranking => '榜单',
        ListSource.recommend => '推荐',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _body(),
    );
  }

  Widget _body() {
    if (_items.isEmpty) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.grey),
              const SizedBox(height: 8),
              Text('加载失败：$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => setState(() {
                  _error = null;
                  _hasMore = true;
                  _loadMore();
                }),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
      return const EmptyView();
    }

    final footer = _hasMore || _loading;
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 0.62,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: _items.length + (footer ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          if (_loading) {
            return const Center(child: SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
          }
          // 出错但已有内容：给一个重试块。
          if (_error != null) {
            return Center(
              child: TextButton(
                onPressed: () => _loadMore(),
                child: const Text('加载失败，点击重试'),
              ),
            );
          }
          return const SizedBox.shrink();
        }
        final it = _items[i];
        return ContentTile(
          item: it,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DetailPage(
                kind: it.kind, id: it.id, title: it.title, source: it.source),
          )),
        );
      },
    );
  }
}

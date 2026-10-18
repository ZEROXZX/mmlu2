import 'package:flutter/material.dart';

import '../../data/models/content.dart';
import 'async_view.dart';
import 'content_tile.dart';

/// 可分页的内容网格：**滚动到底自动加载下一页**。
///
/// 首页/分类的「更多」（[ContentListPage]）与搜索结果（[SearchTab]）共用。
/// 特性：按 `kind:id:source` 去重、本页不足或整页无新增即停止、首屏/追加失败可重试。
class PaginatedContentList extends StatefulWidget {
  const PaginatedContentList({
    super.key,
    required this.loader,
    required this.onTap,
    this.pageSize = 20,
    this.emptyText = '无结果',
  });

  final Future<List<ContentItem>> Function(int page) loader;
  final void Function(ContentItem item) onTap;
  final int pageSize;
  final String emptyText;

  @override
  State<PaginatedContentList> createState() => _PaginatedContentListState();
}

class _PaginatedContentListState extends State<PaginatedContentList> {
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
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  /// 下拉刷新：清空后从第 1 页重新加载。
  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _items.clear();
      _seen.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final next = _page + 1;
    try {
      final items = await widget.loader(next);
      if (!mounted) return;
      setState(() {
        _page = next;
        for (final it in items) {
          if (_seen.add('${it.kind.tag}:${it.id}:${it.source}')) _items.add(it);
        }
        if (items.length < widget.pageSize) {
          _hasMore = false;
        } else {
          _hasMore = true;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
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
                onPressed: () {
                  // 先同步重置状态再触发异步加载，别在 setState 里 fire-and-forget。
                  setState(() {
                    _error = null;
                    _hasMore = true;
                  });
                  _loadMore();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
      return EmptyView(text: widget.emptyText);
    }

    final footer = _hasMore || _loading;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
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
              return const Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (_error != null) {
              return Center(
                child: TextButton(
                  onPressed: _loadMore,
                  child: const Text('加载失败，点击重试'),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          final it = _items[i];
          return AutomaticKeepAlive(child: ContentTile(item: it, onTap: () => widget.onTap(it)));
        },
      ),
    );
  }
}

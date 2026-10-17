import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../widgets/async_view.dart';
import '../widgets/content_tile.dart';
import 'detail_page.dart';

enum ListSource { latest, ranking, recommend }

/// 内容列表页（最新 / 榜单 / 推荐 / 搜索）。
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
  late Future<List<ContentItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ContentItem>> _load() {
    final repo = context.read<AppContainer>().contentRepo;
    if (widget.keywords != null) {
      return repo.search(widget.kind, widget.keywords!);
    }
    return switch (widget.source) {
      ListSource.latest => repo.listNew(widget.kind),
      ListSource.ranking => repo.listRanking(widget.kind),
      ListSource.recommend => repo.listRecommend(widget.kind),
    };
  }

  String get _title => widget.title ?? '${widget.kind.label}·${_sourceLabel(widget.source)}';

  static String _sourceLabel(ListSource s) => switch (s) {
        ListSource.latest => '最新',
        ListSource.ranking => '榜单',
        ListSource.recommend => '推荐',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: AsyncView<List<ContentItem>>(
        future: _future,
        onRetry: () => setState(() => _future = _load()),
        empty: const EmptyView(),
        builder: (context, items) => ContentGrid(
          items: items,
          onTap: (it) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DetailPage(kind: it.kind, id: it.id, title: it.title, source: it.source),
          )),
        ),
      ),
    );
  }
}

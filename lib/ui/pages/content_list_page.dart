import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../widgets/paginated_content.dart';
import 'detail_page.dart';

enum ListSource { latest, ranking, recommend }

/// 内容列表页（最新 / 榜单 / 推荐 / 搜索）。
///
/// 支持**滚动到底自动加载下一页**（首页/分类的「更多」即进入本页）。
class ContentListPage extends StatelessWidget {
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

  static const _pageSize = 20;

  String get _title => title ?? '${kind.label}·${_sourceLabel(source)}';

  static String _sourceLabel(ListSource s) => switch (s) {
        ListSource.latest => '最新',
        ListSource.ranking => '榜单',
        ListSource.recommend => '推荐',
      };

  Future<List<ContentItem>> _loadPage(BuildContext context, int page) {
    final repo = context.read<AppContainer>().contentRepo;
    if (keywords != null) {
      return repo.search(kind, keywords!, pages: page, counts: _pageSize);
    }
    return switch (source) {
      ListSource.latest => repo.listNew(kind, pages: page, counts: _pageSize),
      ListSource.ranking =>
        repo.listRanking(kind, pages: page, counts: _pageSize),
      ListSource.recommend =>
        repo.listRecommend(kind, pages: page, counts: _pageSize),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: PaginatedContentList(
        loader: (page) => _loadPage(context, page),
        onTap: (it) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DetailPage(
              kind: it.kind, id: it.id, title: it.title, source: it.source),
        )),
      ),
    );
  }
}

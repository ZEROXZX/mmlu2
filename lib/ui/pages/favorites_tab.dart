import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../widgets/paginated_content.dart';
import 'detail_page.dart';

/// 收藏：按内容种类查看收藏列表（支持分页加载）。
class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  static const _kinds = [
    ContentKind.animat,
    ContentKind.comicNs,
    ContentKind.comicAv,
    ContentKind.fiction,
  ];
  ContentKind _kind = ContentKind.animat;

  Future<void> _open(ContentItem it) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailPage(
        kind: it.kind,
        id: it.id,
        title: it.title,
        source: it.source,
      ),
    ));
    // 详情页里可能取消了收藏，返回后刷新列表
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final k in _kinds)
                ChoiceChip(
                  label: Text(k.label),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
        ),
        Expanded(
          child: PaginatedContentList(
            key: ValueKey(_kind),
            loader: (page) => context
                .read<AppContainer>()
                .contentRepo
                .favorites(_kind, pages: page),
            onTap: _open,
            emptyText: '暂无收藏',
          ),
        ),
      ],
    );
  }
}

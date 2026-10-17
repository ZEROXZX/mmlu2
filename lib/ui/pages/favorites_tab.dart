import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../widgets/async_view.dart';
import '../widgets/content_tile.dart';
import 'detail_page.dart';

/// 收藏：按内容种类查看收藏列表。
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
  late Future<List<ContentItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ContentItem>> _load() =>
      context.read<AppContainer>().contentRepo.favorites(_kind);

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
                  onSelected: (_) => setState(() {
                    _kind = k;
                    _future = _load();
                  }),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<List<ContentItem>>(
            future: _future,
            onRetry: () => setState(() => _future = _load()),
            empty: const EmptyView(text: '暂无收藏'),
            builder: (context, items) => ContentGrid(
              items: items,
              onTap: (it) => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DetailPage(kind: it.kind, id: it.id, title: it.title, source: it.source),
              )),
            ),
          ),
        ),
      ],
    );
  }
}

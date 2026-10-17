import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../widgets/async_view.dart';
import '../widgets/cover_image.dart';
import 'detail_page.dart';

/// 观看/阅读历史页。
///
/// 注意：`GET v2/{type}/history` 服务端常返错（动画返空、漫画/小说 500/502，
/// 见 PROTOCOL.md §9D），此处对错误做友好降级但仍可重试。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  ContentKind _kind = ContentKind.animat;
  int _range = 1;
  late Future<List<ContentItem>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<AppContainer>().contentRepo.histories(_kind, range: _range);
  }

  Future<void> _delete(ContentItem it) async {
    final c = context.read<AppContainer>();
    try {
      await c.contentRepo.deleteHistory(_kind, [it.id]);
    } catch (_) {}
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('观看历史'),
        actions: [
          PopupMenuButton<int>(
            initialValue: _range,
            tooltip: '范围',
            onSelected: (v) => setState(() {
              _range = v;
              _reload();
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: Text('全部')),
              PopupMenuItem(value: 1, child: Text('最近')),
              PopupMenuItem(value: 2, child: Text('更早')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<ContentKind>(
              segments: const [
                ButtonSegment(value: ContentKind.animat, label: Text('动画')),
                ButtonSegment(value: ContentKind.comicNs, label: Text('漫画')),
                ButtonSegment(value: ContentKind.fiction, label: Text('小说')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _reload();
              }),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncView<List<ContentItem>>(
              future: _future,
              empty: const EmptyView(text: '暂无历史记录'),
              onRetry: () => setState(_reload),
              builder: (context, items) => ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final it = items[i];
                  return ListTile(
                    leading: CoverImage(item: it, width: 44, height: 60),
                    title: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(it.series ?? it.tags.take(3).join(' / '),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(it),
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DetailPage(
                        kind: it.kind,
                        id: it.id,
                        title: it.title,
                        source: it.source,
                      ),
                    )),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

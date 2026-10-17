import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../widgets/async_view.dart';
import '../widgets/content_tile.dart';
import 'detail_page.dart';

/// 搜索：选择内容种类 + 关键词。
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  ContentKind _kind = ContentKind.animat;
  final _kw = TextEditingController();
  Future<List<ContentItem>>? _future;

  void _run() {
    final kw = _kw.text.trim();
    if (kw.isEmpty) return;
    setState(() {
      _future = context.read<AppContainer>().contentRepo.search(_kind, kw);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              DropdownButton<ContentKind>(
                value: _kind,
                onChanged: (k) => setState(() => _kind = k ?? _kind),
                // 图集无搜索接口（v2/v3/search/*/photo 均 404），故不提供。
                items: [
                  for (final k in ContentKind.values)
                    if (k != ContentKind.photo)
                      DropdownMenuItem(value: k, child: Text(k.label)),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _kw,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _run(),
                  decoration: const InputDecoration(
                    hintText: '输入关键词',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _run, child: const Text('搜索')),
            ],
          ),
        ),
        Expanded(
          child: _future == null
              ? const EmptyView(text: '输入关键词开始搜索')
              : AsyncView<List<ContentItem>>(
                  future: _future!,
                  onRetry: _run,
                  empty: const EmptyView(text: '无结果'),
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

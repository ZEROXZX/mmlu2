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
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _history = context.read<AppContainer>().searchHistoryStore.load();
  }

  void _run() {
    final kw = _kw.text.trim();
    if (kw.isEmpty) return;
    final c = context.read<AppContainer>();
    c.searchHistoryStore.add(kw);
    setState(() {
      _history = c.searchHistoryStore.load();
      _future = c.contentRepo.search(_kind, kw);
    });
  }

  void _searchKw(String kw) {
    _kw.text = kw;
    _run();
  }

  Future<void> _removeHistory(String kw) async {
    final c = context.read<AppContainer>();
    await c.searchHistoryStore.remove(kw);
    if (mounted) setState(() => _history = c.searchHistoryStore.load());
  }

  Future<void> _clearHistory() async {
    final c = context.read<AppContainer>();
    await c.searchHistoryStore.clear();
    if (mounted) setState(() => _history = c.searchHistoryStore.load());
  }

  /// 搜索历史（无上限；点按重搜，逐条删除或清空）。空闲时显示。
  Widget _historyBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('搜索历史',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
              const Spacer(),
              TextButton(
                onPressed: _clearHistory,
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final kw in _history)
                InputChip(
                  label: Text(kw),
                  onPressed: () => _searchKw(kw),
                  onDeleted: () => _removeHistory(kw),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
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
        if (_future == null && _history.isNotEmpty) _historyBar(),
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

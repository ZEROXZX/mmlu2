import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../widgets/content_tile.dart';
import 'content_list_page.dart';
import 'detail_page.dart';

/// 首页：为每种内容展示「最新」横向分区。
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  static const _kinds = [
    ContentKind.animat,
    ContentKind.comicNs,
    ContentKind.comicAv,
    ContentKind.fiction,
    ContentKind.photo,
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // BannerCarousel removed per request
        for (final k in _kinds) _Section(kind: k),
      ],
    );
  }
}

class _Section extends StatefulWidget {
  const _Section({required this.kind});

  final ContentKind kind;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late Future<List<ContentItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppContainer>().contentRepo.listNew(widget.kind);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Row(
            children: [
              Text(widget.kind.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ContentListPage(kind: widget.kind, title: '${widget.kind.label}·最新'),
                )),
                child: const Text('更多'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: FutureBuilder<List<ContentItem>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data ?? const [];
              if (items.isEmpty) {
                return const Center(child: Text('暂无内容', style: TextStyle(color: Colors.grey)));
              }
              return HorizontalContentRow(
                items: items,
                onTap: (it) => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DetailPage(kind: it.kind, id: it.id, title: it.title, source: it.source),
                )),
              );
            },
          ),
        ),
      ],
    );
  }
}

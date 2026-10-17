import 'package:flutter/material.dart';

import '../../data/models/content.dart';
import 'content_list_page.dart';

/// 分类：按内容种类 × 榜单类型进入列表。
class CategoryTab extends StatelessWidget {
  const CategoryTab({super.key});

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
      padding: const EdgeInsets.all(12),
      children: [
        for (final k in _kinds)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in ListSource.values)
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ContentListPage(
                              kind: k,
                              source: s,
                              title: '${k.label}·${_label(s)}',
                            ),
                          )),
                          child: Text(_label(s)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _label(ListSource s) => switch (s) {
        ListSource.latest => '最新',
        ListSource.ranking => '榜单',
        ListSource.recommend => '推荐',
      };
}

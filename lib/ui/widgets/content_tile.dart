import 'package:flutter/material.dart';

import '../../data/models/content.dart';
import 'cover_image.dart';

/// 内容网格卡片。
class ContentTile extends StatelessWidget {
  const ContentTile({super.key, required this.item, required this.onTap});

  final ContentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CoverImage(item: item, width: double.infinity, height: double.infinity),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// 内容网格。
class ContentGrid extends StatelessWidget {
  const ContentGrid({super.key, required this.items, required this.onTap});

  final List<ContentItem> items;
  final void Function(ContentItem) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 0.62,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => ContentTile(item: items[i], onTap: () => onTap(items[i])),
    );
  }
}

/// 横向内容条（首页分区用）。
class HorizontalContentRow extends StatelessWidget {
  const HorizontalContentRow({super.key, required this.items, required this.onTap});

  final List<ContentItem> items;
  final void Function(ContentItem) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final it = items[i];
          return SizedBox(
            width: 110,
            child: InkWell(
              onTap: () => onTap(it),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoverImage(item: it, width: 110, height: 150),
                  const SizedBox(height: 4),
                  Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

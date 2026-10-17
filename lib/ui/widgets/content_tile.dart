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
    // 小说条目没有封面（无 `cover` 字段），图片位会变成破图；改为纯文字卡片。
    if (item.kind == ContentKind.fiction) return _FictionTile(item: item, onTap: onTap);
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

/// 小说专用纯文字卡片（无封面）。
class _FictionTile extends StatelessWidget {
  const _FictionTile({required this.item, required this.onTap});

  final ContentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = (item.tag != null && item.tag!.isNotEmpty)
        ? item.tag!
        : (item.desc ?? '');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.menu_book_outlined, size: 22, color: scheme.primary),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                item.title,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            if (sub.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
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
                  if (it.kind == ContentKind.fiction)
                    SizedBox(
                      width: 110,
                      height: 150,
                      child: _FictionTile(item: it, onTap: () => onTap(it)),
                    )
                  else
                    CoverImage(item: it, width: 110, height: 150),
                  const SizedBox(height: 4),
                  if (it.kind != ContentKind.fiction)
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

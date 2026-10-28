import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';

/// 封面/缩略图：拉取密文 → 解密 → 显示。带进程内缓存。
///
/// 必须是 StatefulWidget：future 只在 initState 创建一次，避免父级每次
/// rebuild 都新建 future（导致 FutureBuilder 闪 loading、滚动卡顿）。
class CoverImage extends StatefulWidget {
  const CoverImage({
    super.key,
    required this.item,
    this.width = 100,
    this.height = 140,
    this.radius = 8,
  });

  final ContentItem item;
  final double width;
  final double height;
  final double radius;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  static final Map<String, Uint8List> _cache = {};

  late final Future<Uint8List?> _future = _load();

  Future<Uint8List?> _load() async {
    final rs = context.read<AppContainer>().resourceService;
    final item = widget.item;
    final key = '${item.kind.tag}:${item.id}:${item.thumbPath ?? item.cover?.path}';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      Uint8List? bytes;
      if (item.kind == ContentKind.animat) {
        final p = item.thumbPath;
        if (p == null || p.isEmpty) return null;
        bytes = await rs.fetchAnimatImage(p);
      } else {
        final c = item.cover;
        if (c == null || !c.isValid) return null;
        bytes = await rs.fetchDecrypted(item.kind, c);
      }
      if (bytes.isNotEmpty) {
        // 进程内缓存：超上限保留最近一半，避免无上限增长。
        if (_cache.length > 800) {
          final toKeep = _cache.entries.take(400).toList();
          _cache.clear();
          for (final e in toKeep) {
            _cache[e.key] = e.value;
          }
        }
        _cache[key] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<Uint8List?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const ColoredBox(
                color: Color(0x22000000),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final b = snap.data;
            if (b == null || b.isEmpty) {
              return const ColoredBox(
                color: Color(0x11000000),
                child: Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: Colors.black26),
                ),
              );
            }
            return Image.memory(
              b,
              width: widget.width,
              height: widget.height,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Color(0x11000000),
                child: Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.black26),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

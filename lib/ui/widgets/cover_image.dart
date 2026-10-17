import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../../data/service/resource_service.dart';

/// 封面/缩略图：拉取密文 → 解密 → 显示。带进程内缓存。
class CoverImage extends StatelessWidget {
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

  static final Map<String, Uint8List> _cache = {};

  Future<Uint8List?> _load(ResourceService rs) async {
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
      if (bytes.isNotEmpty) _cache[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.read<AppContainer>().resourceService;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: FutureBuilder<Uint8List?>(
          future: _load(rs),
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
                color: Color(0x22000000),
                child: Icon(Icons.broken_image_outlined),
              );
            }
            return Image.memory(b, width: width, height: height, fit: BoxFit.cover);
          },
        ),
      ),
    );
  }
}

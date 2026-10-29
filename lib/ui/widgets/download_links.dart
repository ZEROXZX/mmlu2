import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 弹出「加密 / 解密密钥 / 解密后」三条链接对话框（可逐条或一键复制全部）。
///
/// 用于详情页（下载前即时获取）与下载页（任务/历史条目）两处。
Future<void> showDownloadLinks(
  BuildContext context, {
  required String title,
  String? encrypted,
  String? key,
  String? decrypted,
  String emptyHint = '暂无可用链接（开始下载后可获取）',
  List<ImageLinkItem>? imageLinks,
}) {
  final hasAny = imageLinks?.isNotEmpty == true ||
      [encrypted, key, decrypted].any((v) => v != null && v.isNotEmpty);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasAny)
              Text(emptyHint,
                  style: const TextStyle(fontSize: 13, color: Colors.grey))
            else if (imageLinks != null && imageLinks.isNotEmpty) ...[
              for (final item in imageLinks)
                _imageLinkItem(ctx, item),
            ] else ...[
              _link(ctx, '加密链接', encrypted),
              _link(ctx, '解密密钥链接', key),
              _link(ctx, '解密后链接', decrypted),
            ],
          ],
        ),
      ),
      actions: [
        if (imageLinks != null && imageLinks.isNotEmpty)
          TextButton(
            onPressed: () {
              final all = <String>[
                for (final item in imageLinks)
                  '图${item.index}: ${item.url}\nkey: ${item.key ?? ''} iv: ${item.iv ?? ''}',
              ].join('\n\n');
              Clipboard.setData(ClipboardData(text: all));
              ScaffoldMessenger.of(ctx)
                  .showSnackBar(const SnackBar(content: Text('已复制全部')));
            },
            child: const Text('复制全部'),
          )
        else if (hasAny)
          TextButton(
            onPressed: () {
              final all = <String>[
                if (encrypted != null && encrypted.isNotEmpty)
                  '加密链接: $encrypted',
                if (key != null && key.isNotEmpty) '解密密钥链接: $key',
                if (decrypted != null && decrypted.isNotEmpty)
                  '解密后链接: $decrypted',
              ].join('\n');
              Clipboard.setData(ClipboardData(text: all));
              ScaffoldMessenger.of(ctx)
                  .showSnackBar(const SnackBar(content: Text('已复制全部链接')));
            },
            child: const Text('复制全部'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
      ],
    ),
  );
}

class ImageLinkItem {
  const ImageLinkItem({required this.index, required this.url, this.key, this.iv});
  final int index;
  final String url;
  final String? key;
  final String? iv;
}

Widget _imageLinkItem(BuildContext context, ImageLinkItem item) {
  final text = '图${item.index}: ${item.url}\nkey: ${item.key ?? ''}\niv: ${item.iv ?? ''}';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('图片 ${item.index}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: '复制此图链接+密钥',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已复制')));
              },
            ),
          ],
        ),
        SelectableText(text, style: const TextStyle(fontSize: 11)),
        const Divider(),
      ],
    ),
  );
}

Widget _link(BuildContext context, String label, String? value) {
  if (value == null || value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: SelectableText('$label:\n$value',
              style: const TextStyle(fontSize: 12)),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已复制')));
          },
        ),
      ],
    ),
  );
}

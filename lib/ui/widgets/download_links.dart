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
}) {
  final hasAny =
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
            else ...[
              _link(ctx, '加密链接', encrypted),
              _link(ctx, '解密密钥链接', key),
              _link(ctx, '解密后链接', decrypted),
            ],
          ],
        ),
      ),
      actions: [
        if (hasAny)
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

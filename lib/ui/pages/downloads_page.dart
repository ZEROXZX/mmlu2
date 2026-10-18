import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/service/download_store.dart';
import '../../data/service/download_task.dart';
import '../widgets/async_view.dart';
import '../widgets/download_links.dart';

/// 下载页：任务列表（视频可暂停/恢复/取消，图片/小说仅取消）+ 历史记录 + 并发设置。
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final container = context.read<AppContainer>();
    final mgr = context.watch<DownloadManager>();
    final tasks = mgr.tasks;
    final records = container.downloadStore.load().where((r) {
      return !mgr.hasTask(r.id);
    }).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _toolbar(context, mgr, tasks),
        if (tasks.isEmpty && records.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: EmptyView(text: '暂无下载记录'),
          )
        else ...[
          if (tasks.isNotEmpty) ...[
            _sectionHeader('下载任务 (${tasks.length})'),
            for (final t in tasks) _taskTile(context, mgr, t),
          ],
          if (records.isNotEmpty) ...[
            if (tasks.isNotEmpty) const SizedBox(height: 8),
            _sectionHeader('历史记录 (${records.length})'),
            if (_selected.isNotEmpty) _selectionBar(context, records),
            for (final r in records) _recordTile(context, r),
          ],
        ],
      ],
    );
  }

  // ---- 工具栏：多线程并发数（自由调整） ------------------------------------

  Widget _toolbar(
      BuildContext context, DownloadManager mgr, List<DownloadTask> tasks) {
    final finished = mgr.finishedTasks.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PopupMenuButton<int>(
            tooltip: '下载线程数',
            onSelected: (n) => mgr.concurrency = n,
            itemBuilder: (_) => [
              for (final n in const [1, 2, 4, 8])
                CheckedPopupMenuItem<int>(
                  value: n,
                  checked: n == mgr.concurrency,
                  child: Text('$n 线程'),
                ),
            ],
            child: Chip(
              avatar: const Icon(Icons.tune, size: 18),
              label: Text('${mgr.concurrency} 线程'),
              visualDensity: VisualDensity.compact,
            ),
          ),
          // 图集/漫画下载后是否额外导出单图到相册（默认关，避免与 zip 重复占空间）。
          FilterChip(
            avatar: Icon(
              mgr.exportToGallery
                  ? Icons.photo_library
                  : Icons.photo_library_outlined,
              size: 18,
            ),
            label: const Text('导出相册'),
            selected: mgr.exportToGallery,
            onSelected: (v) => mgr.exportToGallery = v,
            visualDensity: VisualDensity.compact,
            tooltip: '漫画/图集下载后，除 zip 外再存一份单图到相册 Pictures/mmlu',
          ),
          if (finished > 0)
            TextButton.icon(
              onPressed: () => _confirmClearFinished(context, mgr),
              icon: const Icon(Icons.clear_all, size: 18),
              label: Text('清除已结束($finished)'),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
      );

  // ---- 任务条目 -------------------------------------------------------------

  Widget _taskTile(
      BuildContext context, DownloadManager mgr, DownloadTask t) {
    final scheme = Theme.of(context).colorScheme;
    final frac = t.total > 0 ? t.done / t.total : null;
    final statusColor = switch (t.status) {
      DownloadStatus.done => Colors.green,
      DownloadStatus.failed => scheme.error,
      DownloadStatus.cancelled => Colors.grey,
      DownloadStatus.paused => Colors.orange,
      _ => scheme.primary,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${t.title}${t.quality != null ? ' · ${t.quality}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(t.label,
                  style: TextStyle(fontSize: 12, color: statusColor)),
              ..._taskActions(context, mgr, t),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 4,
              color: statusColor,
              backgroundColor: Colors.black12,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(_taskMeta(t),
                    style: const TextStyle(fontSize: 11, color: Colors.black45)),
              ),
              TextButton.icon(
                onPressed: () => _openLinks(context, t),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('复制下载链接', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _taskMeta(DownloadTask t) {
    final parts = <String>[
      switch (t.type) {
        DownloadType.video => '分片 ${t.done}/${t.total}',
        DownloadType.image => '图片 ${t.done}/${t.total}',
        DownloadType.fiction => '章节 ${t.done}/${t.total}',
      },
      _humanSize(t.bytes),
      if (t.status == DownloadStatus.downloading && t.speed > 0)
        '${_humanSize(t.speed.toInt())}/s',
      if (t.status == DownloadStatus.failed && t.error != null)
        t.error!,
    ];
    return parts.join(' · ');
  }

  List<Widget> _taskActions(
      BuildContext context, DownloadManager mgr, DownloadTask t) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap,
            {Color? color}) =>
        IconButton(
          tooltip: tip,
          iconSize: 22,
          icon: Icon(icon, color: color),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
        );

    switch (t.status) {
      case DownloadStatus.queued:
      case DownloadStatus.downloading:
        return [
          if (t.canPause)
            btn(Icons.pause_circle_outline, '暂停', () => mgr.pause(t)),
          btn(Icons.close, '取消', () => mgr.cancel(t), color: Colors.redAccent),
        ];
      case DownloadStatus.paused:
        return [
          if (t.canResume)
            btn(Icons.play_circle_outline, '恢复', () => mgr.resume(t)),
          btn(Icons.close, '取消', () => mgr.cancel(t), color: Colors.redAccent),
        ];
      case DownloadStatus.done:
        return [
          btn(Icons.delete_outline, '删除记录（保留文件）', () => mgr.remove(t)),
        ];
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return [
          if (t.canRetry)
            btn(Icons.refresh, '重试', () => mgr.retry(t)),
          btn(Icons.delete_outline, '删除记录（保留文件）', () => mgr.remove(t)),
        ];
    }
  }

  /// 复制下载链接（加密 / 密钥 / 解密后）——任务与历史条目共用。
  void _openLinks(BuildContext context, DownloadTask t) {
    final r = context.read<AppContainer>().downloadStore
        .load()
        .where((e) => e.id == t.id)
        .toList();
    showDownloadLinks(
      context,
      title: t.title,
      encrypted: t.encryptedUrl ?? (r.isNotEmpty ? r.first.encryptedUrl : null),
      key: t.keyUrl ?? (r.isNotEmpty ? r.first.keyUrl : null),
      decrypted: t.decryptedUrl ?? (r.isNotEmpty ? r.first.decryptedUrl : null),
    );
  }

  // ---- 历史条目（勾选删除 + 三条链接） --------------------------------------

  Widget _selectionBar(BuildContext context, List<DownloadRecord> records) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text('已选 ${_selected.length} 项'),
          const Spacer(),
          TextButton(
            onPressed: () => _deleteMany(context, records),
            child: const Text('删除所选', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _recordTile(BuildContext context, DownloadRecord r) {
    final checked = _selected.contains(r.id);
    final stale = r.status != 'done';
    return ListTile(
      leading: Checkbox(
        value: checked,
        onChanged: (v) => setState(() {
          if (v == true) {
            _selected.add(r.id);
          } else {
            _selected.remove(r.id);
          }
        }),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
                (() {
                  try {
                    final p = r.filePath;
                    if (p.isEmpty) return r.title;
                    final base = p.split('/').last;
                    if (base.isEmpty) return r.title;
                    final name = base.replaceAll(RegExp(r'\.\w+$'), '');
                    return name.isEmpty ? r.title : name;
                  } catch (_) {
                    return r.title;
                  }
                })(),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (stale)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                r.status == 'failed' ? '失败' : '中断',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${r.kind}${r.quality != null ? ' · ${r.quality}' : ''}'
        ' · ${_humanSize(r.totalBytes)}\n${r.filePath}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '复制下载链接',
            icon: const Icon(Icons.link),
            onPressed: () => showDownloadLinks(
              context,
              title: r.title,
              encrypted: r.encryptedUrl,
              key: r.keyUrl,
              decrypted: r.decryptedUrl,
            ),
          ),
          IconButton(
            tooltip: '删除记录（保留文件）',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteOne(context, r),
          ),
        ],
      ),
      onTap: () => showDownloadLinks(
        context,
        title: r.title,
        encrypted: r.encryptedUrl,
        key: r.keyUrl,
        decrypted: r.decryptedUrl,
      ),
    );
  }

  // ---- 删除 -----------------------------------------------------------------

  Future<void> _deleteOne(BuildContext context, DownloadRecord r) async {
    final c = context.read<AppContainer>();
    final mgr = context.read<DownloadManager>();
    final t = mgr.byId(r.id);
    if (t != null && t.isActive) return; // 进行中任务走任务区的取消
    // 只删记录，保留本地文件（用户确认）。
    if (t != null) await mgr.remove(t);
    await c.downloadStore.removeMany([r.id]);
    if (mounted) setState(() => _selected.remove(r.id));
  }

  Future<void> _deleteMany(
      BuildContext context, List<DownloadRecord> all) async {
    final c = context.read<AppContainer>();
    final mgr = context.read<DownloadManager>();
    for (final r in all.where((r) => _selected.contains(r.id))) {
      final t = mgr.byId(r.id);
      if (t != null && t.isActive) continue;
      // 只删记录，保留本地文件（用户确认）。
      if (t != null) await mgr.remove(t);
    }
    await c.downloadStore.removeMany(_selected.toList());
    if (mounted) setState(_selected.clear);
  }

  Future<void> _confirmClearFinished(
      BuildContext context, DownloadManager mgr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清除已结束任务'),
        content: const Text('仅移除任务列表条目，下载文件保留在本地。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清除')),
        ],
      ),
    );
    if (ok == true) await mgr.clearFinished();
  }

  static String _humanSize(int bytes) {
    if (bytes <= 0) return '0B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)}${units[i]}';
  }
}

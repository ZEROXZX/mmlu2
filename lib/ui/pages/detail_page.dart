import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../../data/repo/content_repo.dart';
import '../../data/service/download_task.dart';
import '../../data/service/stream_service.dart';
import '../widgets/async_view.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_links.dart';
import 'content_list_page.dart';
import 'player_page.dart';
import 'reader_page.dart';

/// 内容详情页。按种类展示章节/分集，并提供阅读、播放、下载。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.kind, required this.id, this.title, this.source});

  final ContentKind kind;
  final int id;
  final String? title;
  final String? source;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Future<ContentDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppContainer>().contentRepo.detail(widget.kind, widget.id, source: widget.source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? widget.kind.label)),
      body: AsyncView<ContentDetail>(
        future: _future,
        onRetry: () => setState(() =>
            _future = context.read<AppContainer>().contentRepo.detail(widget.kind, widget.id, source: widget.source)),
        builder: (context, detail) => _Body(kind: widget.kind, id: widget.id, detail: detail),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.kind, required this.id, required this.detail});

  final ContentKind kind;
  final int id;
  final ContentDetail detail;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _fav = false;
  bool _favBusy = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    return ListView(
      children: [
        _header(d.item),
        _metaSection(d.item),
        const Divider(height: 1),
        ..._actions(d),
        const Divider(height: 1),
        ..._content(d),
        ..._samelike(d),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _header(ContentItem item) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverImage(item: item, width: 110, height: 150),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (item.tags.isNotEmpty)
                  Text('标签：${item.tags.join(' / ')}', style: const TextStyle(color: Colors.grey))
                else if (item.tag != null)
                  Text('标签：${item.tag}', style: const TextStyle(color: Colors.grey)),
                if (item.series != null && item.series!.isNotEmpty)
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ContentListPage(
                        kind: widget.kind,
                        keywords: item.series,
                        title: '系列·${item.series}',
                      ),
                    )),
                    child: Text(
                      '系列：${item.series} ›',
                      style: const TextStyle(color: Colors.blue),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    item.desc ?? '',
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 作品详细（元信息）：系列 / 季 / 集 / 时长 / 播放量 / 发行 / 制作 / 来源 / 编号。
  Widget _metaSection(ContentItem item) {
    final raw = item.raw ?? const <String, dynamic>{};
    String s(Object? v) => (v ?? '').toString().trim();
    final rows = <MapEntry<String, String>>[
      if (s(item.series).isNotEmpty) MapEntry('系列', s(item.series)),
      if ((item.season ?? 0) > 0) MapEntry('季', '第 ${item.season} 季'),
      if (item.ep != null) MapEntry('集数', '第 ${item.ep} 集'),
      if (s(item.duration).isNotEmpty) MapEntry('时长', s(item.duration)),
      if ((item.viewCount ?? 0) > 0) MapEntry('播放量', _humanCount(item.viewCount!)),
      if (s(raw['publisher']).isNotEmpty) MapEntry('发行', s(raw['publisher'])),
      if (s(raw['studio']).isNotEmpty) MapEntry('制作', s(raw['studio'])),
      if (s(item.source).isNotEmpty)
        MapEntry('来源', s(item.source) == 'av' ? 'AV' : (s(item.source) == 'ns' ? 'NS' : s(item.source))),
      if (s(item.avkey).isNotEmpty) MapEntry('编号', s(item.avkey)),
      if (s(raw['opened_at']).isNotEmpty) MapEntry('发布时间', s(raw['opened_at'])),
      if (item.tags.isNotEmpty) MapEntry('标签', item.tags.join(' / ')),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('作品信息', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text('${r.key}：',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                  Expanded(
                    child: Text(r.value,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _humanCount(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)} 亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)} 万';
    return '$n';
  }

  List<Widget> _actions(ContentDetail d) {
    final buttons = <Widget>[
      OutlinedButton.icon(
        onPressed: _favBusy ? null : () => _toggleFav(d.item),
        icon: Icon(_fav ? Icons.favorite : Icons.favorite_border),
        label: Text(_fav ? '已收藏' : '收藏'),
      ),
    ];

    if (widget.kind == ContentKind.animat) {
      buttons.add(OutlinedButton.icon(
        onPressed: () => _downloadAnimat(d),
        icon: const Icon(Icons.download),
        label: const Text('合集一起下载'),
      ));
      buttons.add(OutlinedButton.icon(
        onPressed: () => _downloadAnimatPick(d),
        icon: const Icon(Icons.checklist),
        label: const Text('分开下载'),
      ));
    } else if (widget.kind == ContentKind.fiction) {

      buttons.add(OutlinedButton.icon(
        onPressed: () => _downloadFiction(d),
        icon: const Icon(Icons.download),
        label: const Text('下载'),
      ));
    } else {
      buttons.add(OutlinedButton.icon(
        onPressed: () => _downloadImagesZip(d),
        icon: const Icon(Icons.download),
        label: const Text('打包下载'),
      ));
    }

    // 下载前即可获取「加密 / 密钥 / 解密后」链接（无需先下载完成）。
    buttons.add(OutlinedButton.icon(
      onPressed: () => _copyLinks(d),
      icon: const Icon(Icons.link),
      label: const Text('复制链接'),
    ));

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(spacing: 8, children: buttons),
      ),
    ];
  }

  List<Widget> _content(ContentDetail d) {
    switch (widget.kind) {
      case ContentKind.animat:
        return [_animatEpisodes(d)];
      case ContentKind.comicNs:
      case ContentKind.comicAv:
        return [_comicChapters(d)];
      case ContentKind.fiction:
        return [_fictionChapters(d)];
      case ContentKind.photo:
        return [_photoEntry(d)];
    }
  }

  // ---- 动漫：合集（R4） ---------------------------------------------------

  Widget _animatEpisodes(ContentDetail d) {
    final episodes = d.episodes.isNotEmpty ? d.episodes : [d.item];
    final sorted = [...episodes]..sort((a, b) {
        final s = (a.season ?? 0).compareTo(b.season ?? 0);
        return s != 0 ? s : (a.ep ?? 0).compareTo(b.ep ?? 0);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text('合集（分集）', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final e in sorted)
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(e.title.isEmpty ? (e.avkey ?? '第 ${e.ep} 集') : e.title),
            subtitle: Text('${e.season != null ? '第${e.season}季 ' : ''}第${e.ep ?? '-'}集'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '复制下载链接',
                  icon: const Icon(Icons.link, size: 20),
                  onPressed: () => _copyLinksForEpisode(e),
                ),
                IconButton(
                  tooltip: '下载本集',
                  icon: const Icon(Icons.download_outlined, size: 20),
                  onPressed: () => _downloadSingleEpisode(e),
                ),
              ],
            ),
            onTap: () => _play(e, sorted),
          ),
      ],
    );
  }

  // ---- 漫画章节 -----------------------------------------------------------

  Widget _comicChapters(ContentDetail d) {
    if (d.chapters.isEmpty) return const EmptyView(text: '暂无章节');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text('章节', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final ch in d.chapters)
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(ch.title.isEmpty
                ? (ch.number != null ? '第 ${ch.number} 话' : '章节 ${ch.chapterId}')
                : ch.title),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReaderPage(
                kind: widget.kind,
                item: d.item,
                chapterId: ch.chapterId,
                title: ch.title,
              ),
            )),
          ),
      ],
    );
  }

  // ---- 小说章节 -----------------------------------------------------------

  Widget _fictionChapters(ContentDetail d) {
    if (d.fictionChapters.isEmpty) return const EmptyView(text: '暂无章节');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text('目录', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (var i = 0; i < d.fictionChapters.length; i++)
          ListTile(
            leading: Text('${i + 1}'),
            title: Text(d.fictionChapters[i].title.isEmpty
                ? '第 ${i + 1} 章'
                : d.fictionChapters[i].title),
            trailing: IconButton(
              tooltip: '下载本章',
              icon: const Icon(Icons.download_outlined, size: 20),
              onPressed: () => _downloadFiction(d, only: i),
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReaderPage(
                kind: widget.kind,
                item: d.item,
                fictionPath: d.fictionChapters[i].path,
                title: d.fictionChapters[i].title,
              ),
            )),
          ),
      ],
    );
  }

  // ---- 图集 ---------------------------------------------------------------

  Widget _photoEntry(ContentDetail d) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: FilledButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReaderPage(kind: widget.kind, item: d.item, title: d.item.title),
        )),
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('浏览图集'),
      ),
    );
  }

  // ---- 相似作品（samelike） ------------------------------------------------

  List<Widget> _samelike(ContentDetail d) {
    final items = d.samelike.where((e) => e.id != d.item.id).toList();
    if (items.isEmpty) return const [];
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text('相似作品', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      SizedBox(
        height: 196,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 110,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DetailPage(
                        kind: widget.kind,
                        id: it.id,
                        title: it.title,
                        source: it.source,
                      ),
                    )),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CoverImage(item: it, width: 110, height: 148),
                        const SizedBox(height: 4),
                        Text(
                          it.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  // ---- 操作 ---------------------------------------------------------------

  Future<void> _toggleFav(ContentItem item) async {
    setState(() => _favBusy = true);
    try {
      final repo = context.read<AppContainer>().contentRepo;
      if (_fav) {
        await repo.removeFavorite(widget.kind, [item.id]);
      } else {
        await repo.addFavorite(widget.kind, item.id);
      }
      setState(() => _fav = !_fav);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  Future<void> _play(ContentItem item, List<ContentItem> episodes) async {
    final media = item.media;
    if (media.isEmpty) {
      _toast('该分集无播放源');
      return;
    }
    final quality = await _pickQuality(media.keys.toList());
    if (quality == null) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        item: item,
        mediaPath: media[quality]!,
        quality: quality,
        episodes: episodes,
      ),
    ));
  }

  /// R1.7：全集下载——directory 内所有分集一次性入队（画质统一选一次）。
  Future<void> _downloadAnimat(ContentDetail d) async {
    final episodes = d.episodes.isNotEmpty ? d.episodes : [d.item];
    final media = d.item.media.isNotEmpty ? d.item.media : (episodes.first.media);
    if (media.isEmpty) {
      _toast('无播放源');
      return;
    }
    final quality = await _pickQuality(media.keys.toList());
    if (quality == null || !mounted) return;
    final mgr = context.read<DownloadManager>();
    var n = 0;
    for (final e in episodes) {
      final path = e.media[quality];
      if (path == null || path.isEmpty) continue;
      mgr.addVideo(item: e, mediaPath: path, quality: quality);
      n++;
    }
    if (n == 0) {
      _toast('该画质下无可用分集');
      return;
    }
    _toast(n > 1
        ? '已加入下载队列：全集 $n 集（$quality），可在「下载」页暂停/取消'
        : '已加入下载队列，可在「下载」页查看/暂停/取消');
  }

  /// 分开下载——弹勾选框选部分分集，每集生成一个独立任务（画质统一选一次）。
  Future<void> _downloadAnimatPick(ContentDetail d) async {
    final episodes = d.episodes.isNotEmpty ? d.episodes : [d.item];
    final sorted = [...episodes]..sort((a, b) {
        final s = (a.season ?? 0).compareTo(b.season ?? 0);
        return s != 0 ? s : (a.ep ?? 0).compareTo(b.ep ?? 0);
      });
    if (sorted.every((e) => e.media.isEmpty)) {
      _toast('无播放源');
      return;
    }
    final titles = [
      for (var i = 0; i < sorted.length; i++)
        sorted[i].title.isNotEmpty
            ? sorted[i].title
            : '第 ${sorted[i].ep ?? i + 1} 集',
    ];
    final picked = sorted.length == 1
        ? <int>[0]
        : await showDialog<List<int>>(
            context: context,
            builder: (_) => _ChapterPickDialog(
              title: '选择要下载的分集',
              unit: '集',
              titles: titles,
            ),
          );
    if (picked == null || picked.isEmpty) return;
    if (!mounted) return;

    final allMedia = d.item.media.isNotEmpty ? d.item.media : sorted.first.media;
    if (allMedia.isEmpty) {
      _toast('无播放源');
      return;
    }
    final quality = await _pickQuality(allMedia.keys.toList());
    if (quality == null || !mounted) return;

    final mgr = context.read<DownloadManager>();
    var n = 0;
    for (final i in picked) {
      final path = sorted[i].media[quality] ?? allMedia[quality];
      if (path == null || path.isEmpty) continue;
      mgr.addVideo(item: sorted[i], mediaPath: path, quality: quality);
      n++;
    }
    if (n == 0) {
      _toast('该画质下无可用分集');
      return;
    }
    _toast('已加入下载队列：$n 集（$quality），可在「下载」页查看/暂停/复制链接');
  }

  Future<void> _downloadSingleEpisode(ContentItem ep) async {
    final media = ep.media;
    if (media.isEmpty) {
      _toast('该分集无播放源');
      return;
    }
    final quality = await _pickQuality(media.keys.toList());
    if (quality == null || !mounted) return;
    context.read<DownloadManager>().addVideo(
          item: ep,
          mediaPath: media[quality]!,
          quality: quality,
        );
    _toast('已加入下载队列，可在「下载」页查看/暂停/取消');
  }

  /// R1.2：多章下载——弹勾选框（默认全选）；[only] 指定单章时直接入队。
  Future<void> _downloadFiction(ContentDetail d, {int? only}) async {
    final chapters = d.fictionChapters;
    if (chapters.isEmpty) {
      _toast('无章节');
      return;
    }
    var picked = <int>[if (only != null) only];
    if (only == null) {
      if (chapters.length == 1) {
        picked = [0];
      } else {
        final res = await showDialog<List<int>>(
          context: context,
          builder: (_) => _ChapterPickDialog(
            titles: [
              for (var i = 0; i < chapters.length; i++)
                chapters[i].title.isEmpty ? '第 ${i + 1} 章' : chapters[i].title,
            ],
          ),
        );
        if (res == null || res.isEmpty) return;
        picked = res;
      }
    }
    if (!mounted) return;
    context.read<DownloadManager>().addFiction(
          item: d.item,
          chapters: [
            for (final i in picked)
              ResourceRef(path: chapters[i].path, scheme: ImageScheme.plain),
          ],
        );
    _toast('已加入下载队列（${picked.length} 章），可在「下载」页取消');
  }

  Future<void> _downloadImagesZip(ContentDetail d) async {
    final container = context.read<AppContainer>();
    // 漫画需逐章取页；图集直接取页表。
    final pages = <ReadPage>[];
    final scheme = widget.kind == ContentKind.comicNs ? ImageScheme.nsComic : ImageScheme.perImage;
    if (widget.kind == ContentKind.photo) {
      pages.addAll(await container.contentRepo.readPages(widget.kind, id: widget.id));
    } else if (d.chapters.isNotEmpty) {
      for (final ch in d.chapters) {
        pages.addAll(await container.contentRepo.readPages(widget.kind, id: widget.id, chapterId: ch.chapterId));
      }
    } else {
      pages.addAll(await container.contentRepo.readPages(widget.kind, id: widget.id));
    }
    if (pages.isEmpty) {
      _toast('无图片');
      return;
    }
    if (!mounted) return;
    context.read<DownloadManager>().addImages(
          item: d.item,
          pages: pages,
          scheme: scheme,
        );
    _toast('已加入下载队列，可在「下载」页取消');
  }

  /// 复制下载链接：**下载前**即可在详情页获取三条链接（无需先下载）。
  ///
  /// - 动漫：选分集+画质 → 加密(m3u8)/密钥(key.php)/解密后(本机串流代理地址)；
  /// - 小说/图集/漫画：取首个资源的密文地址与密钥。
  Future<void> _copyLinks(ContentDetail d) async {
    final c = context.read<AppContainer>();
    if (widget.kind == ContentKind.animat) {
      final episodes = d.episodes.isNotEmpty ? d.episodes : [d.item];
      final sorted = [...episodes]..sort((a, b) {
          final s = (a.season ?? 0).compareTo(b.season ?? 0);
          return s != 0 ? s : (a.ep ?? 0).compareTo(b.ep ?? 0);
        });
      var ep = sorted.first;
      if (sorted.length > 1) {
        final idx = await _pickSingle('选择分集', [
          for (var i = 0; i < sorted.length; i++)
            sorted[i].title.isNotEmpty
                ? sorted[i].title
                : '第 ${sorted[i].ep ?? i + 1} 集',
        ]);
        if (idx == null || !mounted) return;
        ep = sorted[idx];
      }
      final media = ep.media.isNotEmpty ? ep.media : d.item.media;
      if (media.isEmpty) {
        _toast('无播放源');
        return;
      }
      final quality = await _pickQuality(media.keys.toList());
      if (quality == null || !mounted) return;
      final mediaPath = media[quality]!;
      final baseTitle = ep.title.isNotEmpty ? ep.title : d.item.title;
      try {
        final info = StreamService.parseM3u8(
            await c.streamService.fetchM3u8(mediaPath));
        final decrypted = await c.hlsProxy.playUrl(mediaPath);
        if (!mounted) return;
        await showDownloadLinks(
          context,
          title: '$baseTitle · $quality',
          encrypted: c.streamService.buildM3u8Url(mediaPath),
          key: info.keyUri,
          decrypted: decrypted,
        );
      } catch (e) {
        _toast('获取链接失败：$e');
      }
      return;
    }

    // 小说 / 图集 / 漫画：取首个资源的密文地址与密钥。
    String? enc;
    String? key;
    if (widget.kind == ContentKind.fiction) {
      if (d.fictionChapters.isEmpty) {
        _toast('无章节');
        return;
      }
      enc = c.resourceService.urlFor(widget.kind, d.fictionChapters.first.path);
    } else {
      final pages = <ReadPage>[];
      if (widget.kind == ContentKind.photo) {
        pages.addAll(await c.contentRepo.readPages(widget.kind, id: widget.id));
      } else if (d.chapters.isNotEmpty) {
        pages.addAll(await c.contentRepo.readPages(widget.kind,
            id: widget.id, chapterId: d.chapters.first.chapterId));
      } else {
        pages.addAll(await c.contentRepo.readPages(widget.kind, id: widget.id));
      }
      if (pages.isEmpty) {
        _toast('无图片');
        return;
      }
      enc = c.resourceService.urlFor(widget.kind, pages.first.path);
      key = pages.first.key;
    }
    if (!mounted) return;
    await showDownloadLinks(
      context,
      title: d.item.title,
      encrypted: enc,
      key: key,
      emptyHint: '暂无可复制链接',
    );
  }

  /// 复制**单个分集**的下载链接（详情页分集行内「复制下载链接」按钮）。
  Future<void> _copyLinksForEpisode(ContentItem ep) async {
    final c = context.read<AppContainer>();
    final media = ep.media;
    if (media.isEmpty) {
      _toast('该分集无播放源');
      return;
    }
    final quality = await _pickQuality(media.keys.toList());
    if (quality == null || !mounted) return;
    final mediaPath = media[quality]!;
    try {
      final info = StreamService.parseM3u8(
          await c.streamService.fetchM3u8(mediaPath));
      final decrypted = await c.hlsProxy.playUrl(mediaPath);
      if (!mounted) return;
      await showDownloadLinks(
        context,
        title: '${ep.title.isEmpty ? '第 ${ep.ep} 集' : ep.title} · $quality',
        encrypted: c.streamService.buildM3u8Url(mediaPath),
        key: info.keyUri,
        decrypted: decrypted,
      );
    } catch (e) {
      _toast('获取链接失败：$e');
    }
  }

  Future<int?> _pickSingle(String title, List<String> options) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (var i = 0; i < options.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(i),
              child: Text(options[i],
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }

  Future<String?> _pickQuality(List<String> qualities) {
    const order = ['720', '240', 'intro'];
    final sorted = qualities.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });
    return showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('选择画质'),
        children: [
          for (final q in sorted)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, q),
              child: Text(_qualityLabel(q)),
            ),
        ],
      ),
    );
  }

  static String _qualityLabel(String q) => switch (q) {
        '720' => '720P（1280×720，默认最高）',
        '240' => '240P（≈426×240）',
        'intro' => '预告片',
        _ => q,
      };

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 多项下载勾选框（默认全选，可全选/全不选）。小说章节与动漫分集共用。
class _ChapterPickDialog extends StatefulWidget {
  const _ChapterPickDialog({
    required this.titles,
    this.title = '选择要下载的章节',
    this.unit = '章',
  });

  final List<String> titles;
  final String title;
  final String unit;

  @override
  State<_ChapterPickDialog> createState() => _ChapterPickDialogState();
}

class _ChapterPickDialogState extends State<_ChapterPickDialog> {
  late final Set<int> _sel = {for (var i = 0; i < widget.titles.length; i++) i};

  bool get _all => _sel.length == widget.titles.length;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            CheckboxListTile(
              value: _all,
              dense: true,
              title: const Text('全选'),
              onChanged: (v) => setState(() {
                _sel.clear();
                if (v ?? false) {
                  _sel.addAll(List.generate(widget.titles.length, (i) => i));
                }
              }),
            ),
            const Divider(height: 1),
            for (var i = 0; i < widget.titles.length; i++)
              CheckboxListTile(
                value: _sel.contains(i),
                dense: true,
                title: Text(widget.titles[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _sel.add(i);
                  } else {
                    _sel.remove(i);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _sel.isEmpty
              ? null
              : () => Navigator.pop(context, _sel.toList()..sort()),
          child: Text('下载（${_sel.length} ${widget.unit}）'),
        ),
      ],
    );
  }
}

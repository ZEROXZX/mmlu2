import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/content.dart';
import '../../data/repo/content_repo.dart';
import '../../data/service/download_task.dart';
import '../widgets/async_view.dart';
import '../widgets/cover_image.dart';
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
        label: const Text('下载'),
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
            trailing: IconButton(
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _downloadSingleEpisode(e),
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

/// 小说多章下载勾选框（默认全选，可全选/全不选）。
class _ChapterPickDialog extends StatefulWidget {
  const _ChapterPickDialog({required this.titles});

  final List<String> titles;

  @override
  State<_ChapterPickDialog> createState() => _ChapterPickDialogState();
}

class _ChapterPickDialogState extends State<_ChapterPickDialog> {
  late final Set<int> _sel = {for (var i = 0; i < widget.titles.length; i++) i};

  bool get _all => _sel.length == widget.titles.length;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择要下载的章节'),
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
          child: Text('下载（${_sel.length} 章）'),
        ),
      ],
    );
  }
}

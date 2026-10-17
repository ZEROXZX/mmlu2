/// 内容条目模型（动漫 / 漫画 / 小说 / 图集）。
///
/// 字段来源：docs/PROTOCOL.md §7/§9C 的实测响应。各内容类型字段不完全一致，
/// 这里用一个宽容的联合模型承载，UI 按 [kind] 分支使用。
library;

/// 内容种类。
enum ContentKind {
  animat('animat', '动画'),
  comicNs('comicNs', '漫画'),
  comicAv('comicAv', '漫画'),
  fiction('fiction', '小说'),
  photo('photo', '图集');

  const ContentKind(this.tag, this.label);
  final String tag;
  final String label;
}

/// 封面/图片的解密方案（见 §9C.7）。
enum ImageScheme {
  /// 动漫图：AES-128-CBC，固定 nsAnimeImageDecryptKey/Iv。
  animatImage,

  /// 漫画(ns)：AES-256-CBC，固定 nsComicDecryptKey/Iv。
  nsComic,

  /// 逐图下发：AES-256-CBC，key/iv 由条目携带（Base64）。
  perImage,

  /// 明文（小说正文）。
  plain,
}

/// 一个带密文地址与解密方案的资源引用。
class ResourceRef {
  ResourceRef({
    required this.path,
    this.scheme = ImageScheme.perImage,
    this.key,
    this.iv,
  });

  /// 相对路径（可能无前导 `/`）。host 由内容域决定。
  final String path;

  final ImageScheme scheme;
  final String? key;
  final String? iv;

  bool get isValid => path.isNotEmpty;

  factory ResourceRef.fromJson(
    Map<String, dynamic> j, {
    ImageScheme scheme = ImageScheme.perImage,
    String pathKey = 'cover_path',
  }) =>
      ResourceRef(
        path: (j[pathKey] ?? j['path'] ?? j['image_path'] ?? '').toString(),
        scheme: scheme,
        key: j['key']?.toString(),
        iv: j['iv']?.toString(),
      );
}

/// 统一内容条目。列表项 / 详情 summary 项均用此模型。
class ContentItem {
  ContentItem({
    required this.kind,
    required this.id,
    required this.title,
    this.tag,
    this.tags = const [],
    this.desc,
    this.cover,
    this.thumbPath,
    this.avkey,
    this.source,
    this.series,
    this.season,
    this.ep,
    this.duration,
    this.viewCount,
    this.media = const {},
    this.raw,
  });

  final ContentKind kind;
  final int id;
  final String title;

  /// 单个标签（部分接口如此返回）。
  final String? tag;

  /// 标签数组（部分接口返回 `tag` 为列表或 `tags`）。
  final List<String> tags;

  final String? desc;

  /// 加密封面引用（漫画/图集常见）。
  final ResourceRef? cover;

  /// 动漫缩略图路径（img 域，animatImage 方案）。
  final String? thumbPath;

  /// 动漫媒体标识。
  final String? avkey;

  /// 来源标识：`ns`（v3/nsanimat 接口）或 `av`（v2/combine/animat 接口）。
  final String? source;

  /// 系列名（R1.7/R4 聚合用）。
  final String? series;
  final int? season;
  final int? ep;
  final int? duration;
  final int? viewCount;

  /// 动漫 media 映射：{key -> m3u8 相对路径}，键如 `720`/`240`/`intro`。
  final Map<String, String> media;

  /// 原始 JSON，供详情页取用未建模字段。
  final Map<String, dynamic>? raw;

  /// 画质档位（动漫），按优先级排序。
  List<String> get qualityKeys {
    const order = ['720', '240', 'intro'];
    final keys = media.keys.where(order.contains).toList()
      ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    return keys;
  }

  factory ContentItem.fromJson(ContentKind kind, Map<String, dynamic> j) {
    final media = <String, String>{};
    final m = j['media'];
    if (m is Map) {
      m.forEach((k, v) {
        if (v != null) media['$k'] = '$v';
      });
    }

    ResourceRef? cover;
    if (kind == ContentKind.comicNs) {
      cover = _coverOf(j, ImageScheme.nsComic);
    } else if (kind == ContentKind.comicAv || kind == ContentKind.photo) {
      cover = _coverOf(j, ImageScheme.perImage);
    }

    return ContentItem(
      kind: kind,
      id: _asInt(j['id'] ?? j['_id'] ?? j['comic_id'] ?? j['animate_id']) ?? 0,
      title: (j['title'] ?? j['name'] ?? j['comic_name'] ?? '').toString(),
      tag: j['tag'] is String ? j['tag'] as String : null,
      tags: _asStringList(j['tag'] ?? j['tags']),
      desc: (j['desc'] ?? j['intro'] ?? j['description'])?.toString(),
      cover: cover,
      thumbPath: (j['thumbpath'] ?? j['thumb_path'] ?? j['thumb'])?.toString(),
      avkey: j['avkey']?.toString(),
      source: j['source']?.toString(),
      series: (j['series'] ?? j['series_name'])?.toString(),
      season: _asInt(j['season']),
      ep: _asInt(j['ep'] ?? j['episode'] ?? j['chapter']),
      duration: _asInt(j['duration']),
      viewCount: _asInt(j['view_count'] ?? j['view']),
      media: media,
      raw: j,
    );
  }

  static ResourceRef? _coverOf(Map<String, dynamic> j, ImageScheme scheme) {
    final c = j['cover'];
    if (c is Map) {
      return ResourceRef.fromJson(c.cast<String, dynamic>(), scheme: scheme);
    }
    // 有些接口把封面平铺。
    final p = j['cover_path'];
    if (p != null) {
      return ResourceRef(
        path: p.toString(),
        scheme: scheme,
        key: j['key']?.toString(),
        iv: j['iv']?.toString(),
      );
    }
    return null;
  }
}

/// 漫画章节（directory[] 项）。阅读必须用 [chapterId]（≠ 条目 id，见 §9C.2）。
class Chapter {
  Chapter({
    required this.chapterId,
    required this.comicId,
    required this.title,
    this.number,
    this.cover,
  });

  final int chapterId;
  final int comicId;
  final String title;

  /// 话数序号（`chapter` 字段；与 [chapterId] 不同）。
  final int? number;
  final ResourceRef? cover;

  factory Chapter.fromJson(ContentKind kind, Map<String, dynamic> j) {
    final scheme =
        kind == ContentKind.comicNs ? ImageScheme.nsComic : ImageScheme.perImage;
    return Chapter(
      chapterId: _asInt(j['chapter_id'] ?? j['id']) ?? 0,
      comicId: _asInt(j['comic_id'] ?? j['id']) ?? 0,
      title: (j['title'] ?? j['chapter_name'] ?? j['name'] ?? '').toString(),
      number: _asInt(j['chapter']),
      cover: j['cover'] is Map
          ? ResourceRef.fromJson((j['cover'] as Map).cast<String, dynamic>(),
              scheme: scheme)
          : null,
    );
  }
}

/// 小说章节（`v2/fiction/summary/{id}` 的 `data[]` 项）。
class FictionChapter {
  FictionChapter({required this.title, required this.path, this.pathTw});

  final String title;

  /// 简体正文路径（明文 UTF-8）。
  final String path;

  /// 繁体正文路径。
  final String? pathTw;

  factory FictionChapter.fromJson(Map<String, dynamic> j) => FictionChapter(
        title: (j['title'] ?? j['chapter_name'] ?? j['name'] ?? '').toString(),
        path: (j['filepath'] ?? '').toString(),
        pathTw: j['filepath_tw']?.toString(),
      );
}

/// 阅读/播放页表项。
///
/// - 漫画 ns：`data:[<path>...]`。
/// - 漫画 av / 图集：`data:[{image_path,key,iv}...]`。
class ReadPage {
  ReadPage({required this.path, this.key, this.iv});

  final String path;
  final String? key;
  final String? iv;

  factory ReadPage.fromJson(Map<String, dynamic> j) => ReadPage(
        path: (j['image_path'] ?? j['path'] ?? j['cover_path'] ?? '').toString(),
        key: j['key']?.toString(),
        iv: j['iv']?.toString(),
      );
}

/// 收藏 / 历史列表信封（`{lastPage,total,data[]}`）。
class PagedList<T> {
  PagedList({this.lastPage = 1, this.total = 0, this.data = const []});

  final int lastPage;
  final int total;
  final List<T> data;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

List<String> _asStringList(Object? v) {
  if (v is List) return v.map((e) => '$e').toList();
  if (v is String && v.isNotEmpty) {
    return v.split(RegExp(r'[,，/|]')).where((s) => s.isNotEmpty).toList();
  }
  return const [];
}

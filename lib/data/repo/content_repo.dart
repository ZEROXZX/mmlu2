import '../api/api_service.dart';
import '../models/banner.dart';
import '../models/content.dart';

/// 内容仓库：把 ApiService 的原始响应解析为强类型模型。
///
/// 响应信封 `{"success": <data>}` 已由拦截器解包，故此处直接拿到数据。
class ContentRepo {
  ContentRepo(this._api);

  final ApiService _api;

  // ---- 首页 --------------------------------------------------------------

  // ---- banner ------------------------------------------------------------

  Future<List<BannerItem>> getBanners({int type = 0}) async {
    final res = await _api.comicBanner(type: type);
    final list = _asMapList(_asMap(res)['data'] ?? res);
    return list.map(BannerItem.fromJson).toList();
  }

  /// 各内容「最新 / 榜单 / 推荐」列表。
  Future<List<ContentItem>> listNew(ContentKind kind, {int type = 0, int pages = 1, int counts = 20}) async {
    final res = await switch (kind) {
      ContentKind.animat => _api.animatNew(type: type, pages: pages, counts: counts),
      ContentKind.comicNs => _api.comicNew(source: 'ns', type: type, pages: pages, counts: counts),
      ContentKind.comicAv => _api.comicNew(source: 'av', type: type, pages: pages, counts: counts),
      ContentKind.fiction => _api.fictionNew(type: type, pages: pages, counts: counts),
      ContentKind.photo => _api.photoNew(type: type, pages: pages, counts: counts),
    };
    return _parseItems(kind, res);
  }

  Future<List<ContentItem>> listRanking(ContentKind kind, {int type = 0, int pages = 1, int counts = 20, int range = 1}) async {
    final res = await switch (kind) {
      ContentKind.animat => _api.animatRanking(type: type, pages: pages, counts: counts, range: range),
      ContentKind.comicNs => _api.comicRanking(source: 'ns', type: type, pages: pages, counts: counts, range: range),
      ContentKind.comicAv => _api.comicRanking(source: 'av', type: type, pages: pages, counts: counts, range: range),
      ContentKind.fiction => _api.fictionRanking(type: type, pages: pages, counts: counts, range: range),
      ContentKind.photo => _api.photoRanking(type: type, pages: pages, counts: counts, range: range),
    };
    return _parseItems(kind, res);
  }

  Future<List<ContentItem>> listRecommend(ContentKind kind, {int type = 0, int pages = 1, int counts = 20}) async {
    final res = await switch (kind) {
      ContentKind.animat => _api.animatRecommend(type: type, pages: pages, counts: counts),
      ContentKind.comicNs => _api.comicRecommend(source: 'ns', type: type, pages: pages, counts: counts),
      ContentKind.comicAv => _api.comicRecommend(source: 'av', type: type, pages: pages, counts: counts),
      ContentKind.fiction => _api.fictionRecommend(type: type, pages: pages, counts: counts),
      ContentKind.photo => _api.photoRecommend(type: type, pages: pages, counts: counts),
    };
    return _parseItems(kind, res);
  }

  // ---- 搜索 --------------------------------------------------------------

  Future<List<ContentItem>> search(ContentKind kind, String keywords, {int sort = 0, int pages = 1, int counts = 20}) async {
    final res = await switch (kind) {
      ContentKind.comicNs => _api.searchNs('comic', keywords: keywords, sort: sort, pages: pages, counts: counts),
      ContentKind.comicAv => _api.searchData('comic', keywords: keywords, sort: sort, pages: pages, counts: counts),
      ContentKind.fiction => _api.search('fiction', keywords: keywords, sort: sort, pages: pages, counts: counts),
      ContentKind.animat => _api.search('animat', keywords: keywords, sort: sort, pages: pages, counts: counts),
      ContentKind.photo => _api.search('photo', keywords: keywords, sort: sort, pages: pages, counts: counts),
    };
    return _parseItems(kind, res);
  }

  Future<Object?> searchTag() => _api.searchTag();

  // ---- 详情 --------------------------------------------------------------

  /// 内容详情。
  ///
  /// - 动漫：`episodes` 为 `directory[]`（含分集 media）；`item` 为 `summary[0]`。
  ///   动漫分 `ns`（`v3/nsanimat`）与 `av`（`v2/combine/animat`）两套接口，用
  ///   [source] 区分（`av` 的 media 路径为 `/v1/animat/...`）。
  /// - 漫画：`chapters` 为 `directory[]`（含 `chapter_id`）。
  /// - 小说：`fictionChapters` 为 `data[]`（含 `filepath`）。
  /// - 图集：`item` 取自返回体；页表用 [readPages]。
  Future<ContentDetail> detail(ContentKind kind, int id, {String? source}) async {
    final res = await switch (kind) {
      ContentKind.comicNs => _api.comicNsDetail(id),
      ContentKind.comicAv => _api.comicAvDetail(id),
      ContentKind.animat => source == 'av' ? _api.animatDetail(id) : _api.nsAnimatDetail(id),
      ContentKind.fiction => _api.fictionSummary(id),
      ContentKind.photo => _api.photoRead(id: id),
    };
    final map = _asMap(res);

    if (kind == ContentKind.fiction) {
      final chapters = _asMapList(map['data'] ?? res)
          .map(FictionChapter.fromJson)
          .where((c) => c.path.isNotEmpty)
          .toList();
      final first = _asMapList(map['data'] ?? res);
      final item = ContentItem.fromJson(
        kind,
        first.isNotEmpty ? first.first : map,
      );
      return ContentDetail(
        item: item,
        fictionChapters: chapters,
        samelike: _asMapList(map['samelike'])
            .map((e) => ContentItem.fromJson(kind, e))
            .toList(),
      );
    }

    if (kind == ContentKind.photo) {
      final item = ContentItem.fromJson(kind, map);
      // 图集详情是页表（无 samelike），相似作品走独立接口 v3/photo/similar。
      var similar = const <ContentItem>[];
      try {
        similar = _parseItems(kind, await _api.photoSimilar(id));
      } catch (_) {}
      return ContentDetail(item: item, samelike: similar);
    }

    final summaryRaw = map['summary'];
    final summary0 = summaryRaw is List && summaryRaw.isNotEmpty
        ? (summaryRaw.first as Map).cast<String, dynamic>()
        : map;
    final item = ContentItem.fromJson(kind, summary0);
    final samelike = _asMapList(map['samelike'])
        .map((e) => ContentItem.fromJson(kind, e))
        .toList();

    final dirRaw = _asMapList(map['directory']);
    if (kind == ContentKind.animat) {
      final episodes = dirRaw.map((e) => ContentItem.fromJson(kind, e)).toList();
      return ContentDetail(item: item, episodes: episodes, samelike: samelike);
    }

    final chapters = dirRaw.map((e) => Chapter.fromJson(kind, e)).toList();
    return ContentDetail(item: item, chapters: chapters, samelike: samelike);
  }

  /// 阅读页表。
  Future<List<ReadPage>> readPages(ContentKind kind, {required int id, int? chapterId}) async {
    switch (kind) {
      case ContentKind.comicNs:
        final res = await _api.comicNsRead(comicId: chapterId ?? id);
        final list = _asList(_asMap(res)['data'] ?? res);
        return list.map((e) => ReadPage(path: e.toString())).toList();
      case ContentKind.comicAv:
        final res = await _api.comicRead(chapterId: chapterId ?? id);
        final list = _asMapList(_asMap(res)['data'] ?? res);
        return list.map(ReadPage.fromJson).toList();
      case ContentKind.photo:
        final res = await _api.photoRead(id: id);
        final list = _asMapList(_asMap(res)['data'] ?? res);
        return list.map(ReadPage.fromJson).toList();
      default:
        return const [];
    }
  }

  /// 小说章节正文（明文）。返回每章的 ResourceRef（scheme=plain）。
  Future<List<ResourceRef>> fictionChapters(int id) async {
    final res = await _api.fictionSummary(id);
    final list = _asMapList(_asMap(res)['data'] ?? res);
    return list
        .map((e) => ResourceRef(
              path: (e['filepath'] ?? e['filepath_tw'] ?? '').toString(),
              scheme: ImageScheme.plain,
            ))
        .where((r) => r.isValid)
        .toList();
  }

  // ---- 收藏 / 历史 --------------------------------------------------------

  Future<List<ContentItem>> favorites(ContentKind kind, {int pages = 1, int counts = 20}) async {
    final res = await _api.favorites(_listType(kind), pages: pages, counts: counts);
    return _parseItems(kind, res);
  }

  Future<List<ContentItem>> histories(ContentKind kind, {int range = 1, int pages = 1, int counts = 20}) async {
    final res = await _api.histories(_listType(kind), range: range, pages: pages, counts: counts);
    return _parseItems(kind, res);
  }

  Future<Object?> addFavorite(ContentKind kind, int id) =>
      _api.addFavorite(kind.tag, id);

  Future<Object?> removeFavorite(ContentKind kind, List<int> ids) =>
      _api.removeFavorite(kind.tag, ids);

  Future<Object?> writeHistory(ContentKind kind, int id, {int? lastPage, double? percent}) =>
      _api.writeHistory(kind.tag, id, lastPage: lastPage, percent: percent);

  Future<Object?> deleteHistory(ContentKind kind, List<int> ids) =>
      _api.deleteHistory(kind.tag, ids);

  // ---- 工具 ----------------------------------------------------------

  /// 收藏/历史列表用的 {type}（comicNs/comicAv → comic）。
  static String _listType(ContentKind kind) {
    switch (kind) {
      case ContentKind.comicNs:
      case ContentKind.comicAv:
        return 'comic';
      default:
        return kind.tag;
    }
  }

  // ---- 解析工具 ----------------------------------------------------------

  List<ContentItem> _parseItems(ContentKind kind, Object? res) {
    final list = _asMapList(_asMap(res)['data'] ?? res);
    return list.map((e) => ContentItem.fromJson(kind, e)).toList();
  }

  static Map<String, dynamic> _asMap(Object? o) =>
      o is Map ? o.cast<String, dynamic>() : <String, dynamic>{};

  static List<Object?> _asList(Object? o) => o is List ? o : const [];

  static List<Map<String, dynamic>> _asMapList(Object? o) {
    if (o is List) {
      return o.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }
}

/// 内容详情聚合。
class ContentDetail {
  ContentDetail({
    required this.item,
    this.episodes = const [],
    this.chapters = const [],
    this.fictionChapters = const [],
    this.pages = const [],
    this.samelike = const [],
  });

  final ContentItem item;

  /// 动漫分集（R1.7/R4 合集）。
  final List<ContentItem> episodes;

  /// 漫画章节。
  final List<Chapter> chapters;

  /// 小说章节。
  final List<FictionChapter> fictionChapters;

  /// 图集/漫画页（可能为空，需 [ContentRepo.readPages] 另取）。
  final List<ReadPage> pages;

  /// 相似作品（`samelike[]`；图集取自 `v3/photo/similar`）。
  final List<ContentItem> samelike;
}

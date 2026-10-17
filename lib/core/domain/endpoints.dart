/// 全量接口路径常量（共 111 条，来自 8 个 Retrofit 接口文件）。
///
/// 分组编号沿用分类文档 docs/PROTOCOL.md 第 7 节。
class Endpoints {
  Endpoints._();

  // 01 应用配置 / 启动 / 行为 (6)
  static const String appInfo = 'v2/common/appinfo';
  static const String vcheck = 'v2/vcheck';
  static const String startup = 'v2/combine/startup';
  static const String news = 'v2/common/news/2';
  static const String advert = 'v3/common/advert';
  static const String behavior = 'v2/behavior';

  // 02 用户 / 账户 (11)
  static const String login = 'v2/user/login';
  static const String checkPassword = 'v2/user/checkPassword';
  static const String forgetPassword = 'v2/user/forgetPassword';
  static const String checkCode = 'v2/user/checkCode';
  static const String userCode = 'v2/user/code';
  static const String userInfo = 'v2/user/info';
  static const String userShare = 'v2/user/share';
  static const String userShareInfo = 'v2/user/shareinfo';
  static const String bindPhone = 'v2/user/bindPhone';
  static const String changePassword = 'v2/user/changePassword';
  static const String changePhone = 'v2/user/changePhone';

  // 03 会员 / 支付 / 注册 (4)
  static const String payments = 'v2/payment/payments';
  static const String paymentBuy = 'v2/payment/buy';
  static const String paymentHistory = 'v2/payment/history';
  static const String register = 'v2/register';

  // 04 漫画 / 图集 (37)
  static const String comicIndex = 'v2/combine/comic/index';
  static const String comicBanner = 'v2/comic/banner';
  static const String comicClassic = 'v2/comic/classic';
  static const String comicContinued = 'v2/comic/continued';
  static const String comicKorea = 'v2/comic/korea';
  static const String comicNew = 'v2/comic/new';
  static const String comicRand = 'v2/comic/rand';
  static const String comicRand2 = 'v2/comic/rand2';
  static const String comicRand3 = 'v2/comic/rand3';
  static const String comicRand4 = 'v2/comic/rand4';
  static const String comicRanking = 'v2/comic/ranking';
  static const String comicRead = 'v2/comic/read';
  static const String comicRecommend = 'v2/comic/recommend';
  static const String comicFavorite = 'v2/comic/favorite';
  static String comicFavoriteId(int id) => 'v2/comic/favorite/$id';
  static const String comicReport = 'v2/comic/report';
  static const String comicInternal = 'v3/combine/data/comic/internal';
  static String comicInternalId(int id) => 'v3/combine/data/comic/internal/$id';
  static const String comicDataFavorite = 'v3/comic/data/favorite';
  static String comicDataFavoriteId(int id) => 'v3/comic/data/favorite/$id';
  static const String comicDataHistory = 'v3/comic/data/history';
  static String comicDataHistoryId(int id) => 'v3/comic/data/history/$id';
  static const String comicDataNew = 'v3/comic/data/new';
  static const String comicDataRanking = 'v3/comic/data/ranking';
  static const String comicDataRecommend = 'v3/comic/data/recommend';
  static const String comicDataRead = 'v3/comic/data/read';
  static const String comicNsCategory = 'v3/comic/ns/category';
  static const String comicNsClassicDetail = 'v3/comic/ns/classic/detail';
  static const String comicNsFavorite = 'v3/comic/ns/favorite';
  static String comicNsFavoriteId(int id) => 'v3/comic/ns/favorite/$id';
  static const String comicNsHistory = 'v3/comic/ns/history';
  static String comicNsHistoryId(int id) => 'v3/comic/ns/history/$id';
  static const String comicNsInternal = 'v3/comic/ns/internal';
  static String comicNsInternalId(int id) => 'v3/comic/ns/internal/$id';
  static const String comicNsKorea = 'v3/comic/ns/korea';
  static const String comicNsNew = 'v3/comic/ns/new';
  static const String comicNsRanking = 'v3/comic/ns/ranking';
  static const String comicNsRead = 'v3/comic/ns/read';
  static const String comicNsRecommend = 'v3/comic/ns/recommend';
  static const String photoRead = 'v3/photo/read';
  static const String photoSimilar = 'v3/photo/similar';
  static const String photoTag = 'v3/photo/tag';
  static const String photoNew = 'v3/photo/new';
  static const String photoRanking = 'v3/photo/ranking';
  static const String photoRecommend = 'v3/photo/recommend';

  // 05 动画 (20)
  static const String animatClassic = 'v2/animat/classic';
  static const String animatContinued = 'v2/animat/continued';
  static const String animatFavorite = 'v2/animat/favorite';
  static String animatFavoriteId(int id) => 'v2/animat/favorite/$id';
  static const String animatHistory = 'v2/animat/history';
  static String animatHistoryId(int id) => 'v2/animat/history/$id';
  static const String animatRand = 'v2/animat/rand';
  static const String animatRand2 = 'v2/animat/rand2';
  static const String animatRand3 = 'v2/animat/rand3';
  static const String animatReport = 'v2/animat/report';
  static const String animatSeries = 'v2/animat/series';
  static const String animatIndex = 'v2/combine/animat/index';
  static const String animatInternal = 'v2/combine/animat/internal';
  static String animatInternalId(int id) => 'v2/combine/animat/internal/$id';
  static const String nsAnimatClassicDetail = 'v3/nsanimat/classic/detail';
  static const String nsAnimatFavorite = 'v3/nsanimat/favorite';
  static String nsAnimatFavoriteId(int id) => 'v3/nsanimat/favorite/$id';
  static const String nsAnimatInternal = 'v3/nsanimat/internal';
  static String nsAnimatInternalId(int id) => 'v3/nsanimat/internal/$id';
  static const String nsAnimatNew = 'v3/nsanimat/new';
  static const String nsAnimatRanking = 'v3/nsanimat/ranking';
  static const String nsAnimatRecommend = 'v3/nsanimat/recommend';

  // 06 小说 (17)
  static const String fictionIndex = 'v2/combine/fiction/index';
  static const String fictionCategoryText = 'v2/fiction/categoryText';
  static const String fictionClassic = 'v2/fiction/classic';
  static const String fictionClassicDetail = 'v2/fiction/classic/detail';
  static const String fictionContinued = 'v2/fiction/continued';
  static const String fictionFavorite = 'v2/fiction/favorite';
  static String fictionFavoriteId(int id) => 'v2/fiction/favorite/$id';
  static const String fictionHistory = 'v2/fiction/history';
  static String fictionHistoryId(int id) => 'v2/fiction/history/$id';
  static const String fictionNew = 'v2/fiction/new';
  static const String fictionRand = 'v2/fiction/rand';
  static const String fictionRand2 = 'v2/fiction/rand2';
  static const String fictionRand3 = 'v2/fiction/rand3';
  static const String fictionRanking = 'v2/fiction/ranking';
  static const String fictionRecommend = 'v2/fiction/recommend';
  static const String fictionReport = 'v2/fiction/report';
  static const String fictionSummary = 'v2/fiction/summary';
  static String fictionSummaryId(int id) => 'v2/fiction/summary/$id';

  // 07 收藏 / 历史 (9) — {type} = comic / animat / fiction
  static String collectFavorite(String type) => 'v2/$type/favorite';
  static String collectFavoriteAll(String type) => 'v2/$type/favoriteAll';
  static String collectHistory(String type) => 'v2/$type/history';
  static String collectDataFavorite(String type) => 'v3/$type/data/favorite';
  static String collectDataFavoriteAll(String type) =>
      'v3/$type/data/favoriteAll';
  static String collectV3Favorite(String type) => 'v3/$type/favorite';
  static String collectNsFavorite(String type) => 'v3/$type/ns/favorite';
  static String collectNsFavoriteAll(String type) =>
      'v3/$type/ns/favoriteAll';

  // 08 搜索 (4)
  static const String searchTag = 'v2/search/tag';
  static String search(String type) => 'v2/search/$type';
  static String searchData(String type) => 'v3/search/data/$type';
  static String searchNs(String type) => 'v3/search/ns/$type';
}

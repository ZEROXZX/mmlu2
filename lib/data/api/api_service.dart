import 'package:dio/dio.dart';

import '../../core/crypto/mmlu_crypto.dart';
import '../../core/domain/domain_store.dart';
import '../../core/domain/endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/app_info_response.dart';
import '../models/login_body.dart';
import '../models/payment.dart';
import '../models/token_response.dart';
import '../models/user_info_response.dart';

/// 接口层。方法命名/路径对照 docs/PROTOCOL.md 第 7 节。
///
/// 通用头 platform/version/payload/ebody 由拦截器自动附加；
/// 响应体自动解密并 jsonDecode。
class ApiService {
  ApiService(this._client);

  final ApiClient _client;

  String _base(DomainType t) => _client.domainStore.urlOf(t);

  /// 拼接绝对 URL。dio 在 path 为绝对地址时忽略 baseUrl。
  /// 域名常量无尾斜杠、Endpoints 路径无前导斜杠，故此处补一个 '/'。
  String _url(DomainType base, String path) {
    final b = _base(base);
    if (b.isEmpty) return path;
    final root = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
    final rel = path.startsWith('/') ? path : '/$path';
    return '$root$rel';
  }

  // ---- 底层 ---------------------------------------------------------------

  Future<Object?> _get(
    DomainType base,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    bool noAuth = false,
  }) =>
      _send(() => _client.dio.get(
            _url(base, path),
            queryParameters: query,
            options: Options(headers: headers, extra: {'noAuth': noAuth}),
          ));

  Future<Object?> _post(
    DomainType base,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    bool noAuth = false,
  }) =>
      _send(() => _client.dio.post(
            _url(base, path),
            data: body,
            queryParameters: query,
            options: Options(headers: headers, extra: {'noAuth': noAuth}),
          ));

  Future<Object?> _put(
    DomainType base,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    bool noAuth = false,
  }) =>
      _send(() => _client.dio.put(
            _url(base, path),
            data: body,
            queryParameters: query,
            options: Options(headers: headers, extra: {'noAuth': noAuth}),
          ));

  Future<Object?> _delete(
    DomainType base,
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _send(() => _client.dio.delete(
            _url(base, path),
            queryParameters: query,
          ));

  /// 确保存在 token（游客自动注册）。启动时与 499 重试时调用。
  Future<void> ensureGuestToken({bool force = false}) =>
      _client.ensureGuestToken(force: force);

  /// 发送请求，并对**瞬时故障**做指数退避重试（连接/超时/空响应）；
  /// 同时保留 token 自愈（unidentify / 499 / 495），对齐参考实现 `call()`。
  Future<Object?> _send(Future<Response<dynamic>> Function() f) async {
    const maxAttempts = 4;
    for (var attempt = 1;; attempt++) {
      try {
        final r = await f();
        // 游客会话未激活（注册后未 startup）时服务端回 200 + `{error:{msg:unidentify}}`：
        // 重新注册（含 startup）后原样重试一次。
        if (_isUnidentify(r.data) && !_client.tokenStore.isLoggedIn) {
          await _client.ensureGuestToken(force: true);
          return (await f()).data;
        }
        // 偶发空响应（网关异常）→ 退避重试。
        if (_isEmpty(r.data) && attempt < maxAttempts) {
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }
        return r.data;
      } on DioException catch (e) {
        final err = e.error;
        final code =
            err is ApiException ? err.statusCode : (e.response?.statusCode ?? -1);
        // 缺/失效 token：补一个游客 token 后原样重试一次（参考实现 call() 的自愈）。
        if ((code == 499 || code == 495) && !_client.tokenStore.isLoggedIn) {
          try {
            await _client.ensureGuestToken(force: true);
            return (await f()).data;
          } on DioException catch (e2) {
            _raise(e2);
          }
        }
        // 瞬时网络故障（连接失败/超时）→ 退避重试。
        if (attempt < maxAttempts && _isTransient(e)) {
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }
        _raise(e);
      }
    }
  }

  static Duration _backoff(int attempt) =>
      Duration(milliseconds: 300 * attempt + (attempt * 137) % 250);

  static bool _isEmpty(Object? d) =>
      d == null || (d is String && d.trim().isEmpty);

  /// 是否瞬时故障（可安全重试）。HTTP 错误（有响应）不算。
  static bool _isTransient(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.connectionError =>
          true,
        DioExceptionType.unknown => e.response == null,
        _ => false,
      };

  static bool _isUnidentify(Object? d) =>
      d is Map && d['error'] is Map && (d['error'] as Map)['msg'] == 'unidentify';

  Never _raise(DioException e) {
    final err = e.error;
    if (err is ApiException) throw err;
    throw ApiException(
      e.response?.statusCode ?? -1,
      e.message ?? 'network error',
      body: e.response?.data,
    );
  }

  static Map<String, dynamic> _map(Object? o) =>
      (o is Map) ? o.cast<String, dynamic>() : <String, dynamic>{};

  // ---- 01 应用配置 ---------------------------------------------------------

  Future<AppInfoResponse> appInfo() async =>
      AppInfoResponse.fromJson(_map(await _get(DomainType.apiData, Endpoints.appInfo)));

  Future<Object?> vcheck(String xPackage) => _get(
        DomainType.apiData,
        Endpoints.vcheck,
        headers: {'x-package': xPackage},
      );

  Future<Object?> startup({int platform = 1}) =>
      _get(DomainType.apiData, Endpoints.startup, query: {'platform': platform});

  Future<Object?> news() => _get(DomainType.apiData, Endpoints.news);

  Future<Object?> advert() => _get(DomainType.apiData, Endpoints.advert);

  Future<Object?> behavior(String type) =>
      _get(DomainType.apiData, Endpoints.behavior, query: {'type': type});

  // ---- 02 用户 -------------------------------------------------------------

  /// 登录。body = {country_codes, phone, password, platform:2}，见 LoginBody。
  ///
  /// 关键：登录**必须**带 `Authorization: Bearer <游客token>`，
  /// 该游客 token 由 [registerDevice] 预先取得并存入 [TokenStore]；
  /// 否则服务端返回 499。成功后返回账号 token（`{success:{token, user_id}}`）。
  Future<TokenResponse> login(LoginBody loginBody) async {
    final data = await _post(
      DomainType.apiData,
      Endpoints.login,
      body: loginBody.toJson(),
    );
    final map = _map(data);
    // 某些形态可能包一层 data；两种都兼容。
    final inner = map['data'] is Map ? (map['data'] as Map).cast<String, dynamic>() : map;
    final res = TokenResponse.fromJson(inner);
    // 服务端在部分失败场景下回 HTTP 200 + 错误信封（无 token）：显式抛出，避免误判登录成功。
    if (res.token == null || res.token!.isEmpty) {
      throw ApiException(
        200,
        extractApiMessage(map, fallback: '登录失败，请检查手机号与密码'),
        body: map,
      );
    }
    return res;
  }

  Future<UserInfoResponse> userInfo() async =>
      UserInfoResponse.fromJson(_map(await _get(DomainType.apiData, Endpoints.userInfo)));

  Future<Object?> checkCode({required String action, required String code}) =>
      _get(DomainType.apiData, Endpoints.checkCode,
          query: {'action': action, 'code': code});

  Future<Object?> sendCode({
    required String action,
    required String countryCodes,
    required String phone,
  }) =>
      _get(DomainType.apiData, Endpoints.userCode, query: {
        'action': action,
        'country_codes': countryCodes,
        'phone': phone,
      });

  Future<Object?> userShare() => _get(DomainType.apiData, Endpoints.userShare);

  // ---- 03 支付 / 注册 ------------------------------------------------------

  Future<PaymentsResponse> payments() async =>
      PaymentsResponse.fromJson(_map(await _get(DomainType.apiData, Endpoints.payments)));

  Future<BuyPaymentResponse> buyPayment({
    required int planId,
    required int paymentId,
  }) async =>
      BuyPaymentResponse.fromJson(_map(await _post(
        DomainType.apiData,
        Endpoints.paymentBuy,
        query: {'plan_id': planId, 'payment_id': paymentId},
      )));

  Future<Object?> paymentHistory({int page = 1, int limit = 20}) =>
      _get(DomainType.apiData, Endpoints.paymentHistory,
          query: {'page': page, 'limit': limit});

  /// 设备引导注册（无 Authorization 头）。
  ///
  /// body = {universal_id, platform:2, model, key, install_channel, install, source}
  /// 其中 key = SHA-256("hcg" + universal_id + "hcg").hexdigest()（沙箱实测通过）。
  /// 服务端返回 `{success:{token, user_id, universal_id}}`，token 为游客 token。
  Future<TokenResponse> registerDevice({
    required String universalId,
    required String model,
    int platform = 2,
    String installChannel = 'com.android.vending',
    String install = '',
    String source = '',
  }) async {
    final body = <String, dynamic>{
      'universal_id': universalId,
      'platform': platform,
      'model': model,
      'key': MmluCrypto.sha256Hex('hcg${universalId}hcg'),
      'install_channel': installChannel,
      'install': install,
      'source': source,
    };
    final data = await _post(
      DomainType.apiData,
      Endpoints.register,
      body: body,
      noAuth: true,
    );
    final map = _map(data);
    final inner =
        map['data'] is Map ? (map['data'] as Map).cast<String, dynamic>() : map;
    return TokenResponse.fromJson(inner);
  }

  // ---- 04 漫画 -------------------------------------------------------------

  Future<Object?> comicIndex({int type = 1, int platform = 1}) =>
      _get(DomainType.apiData, Endpoints.comicIndex,
          query: {'type': type, 'platform': platform});

  Future<Object?> comicClassic({bool categoryType = false, String? xPackage}) =>
      _get(DomainType.apiData, Endpoints.comicClassic,
          query: {'category_type': categoryType},
          headers: xPackage == null ? null : {'x-package': xPackage});

  Future<Object?> comicDetail(int comicId) => _get(
        DomainType.apiData,
        Endpoints.comicInternalId(comicId),
      );

  /// 章节阅读。user_type 为插件/环境能力标志，非 isVip。
  Future<Object?> comicRead({
    required int chapterId,
    int counts = 0,
    int pages = 0,
    bool userType = false,
    String? sdb,
  }) =>
      _get(DomainType.apiData, Endpoints.comicDataRead, query: {
        'chapter_id': chapterId,
        'counts': counts,
        'pages': pages,
        'user_type': userType,
        if (sdb != null) 'sdb': sdb,
      });

  // ---- 05 动画 -------------------------------------------------------------

  Future<Object?> animatIndex({
    int type = 1,
    int platform = 1,
    bool userType = false,
    String? xPackage,
  }) =>
      _get(DomainType.apiData, Endpoints.animatIndex, query: {
        'type': type,
        'platform': platform,
        'user_type': userType,
      }, headers: xPackage == null ? null : {'x-package': xPackage});

  Future<Object?> animatSeries({String? tag, int counts = 0, int pages = 0}) =>
      _get(DomainType.apiData, Endpoints.animatSeries, query: {
        if (tag != null) 'tag': tag,
        'counts': counts,
        'pages': pages,
      });

  // ---- 06 小说 -------------------------------------------------------------

  Future<Object?> fictionIndex({int type = 1, int platform = 1}) =>
      _get(DomainType.apiData, Endpoints.fictionIndex,
          query: {'type': type, 'platform': platform});

  Future<Object?> fictionSummary(int fictionId,
          {bool userType = false, String? xPackage}) =>
      _get(DomainType.apiData, Endpoints.fictionSummaryId(fictionId),
          query: {'user_type': userType},
          headers: xPackage == null ? null : {'x-package': xPackage});

  // ---- 07 收藏 / 历史 ------------------------------------------------------

  /// 收藏列表。[kind] 传 `ContentKind.tag`（comicNs/comicAv/animat/fiction）。
  ///
  /// 路径按种类区分：comicNs → `v3/comic/ns/favorite`，comicAv →
  /// `v3/comic/data/favorite`，其余 → `v2/{kind}/favorite`。
  /// （旧的 `v2/comic/favorite` 服务端已失效，返 500/502。）
  Future<Object?> favorites(String kind, {int counts = 20, int pages = 1, String? source}) =>
      _get(DomainType.apiData, _favoriteBase(kind, source),
          query: {'counts': counts, 'pages': pages});

  /// 历史列表。[range] 服务端要求 ≥1（0 → 400）。[kind] 同 [favorites]。
  Future<Object?> histories(String kind,
          {int range = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData, _historyBase(kind),
          query: {'range': range < 1 ? 1 : range, 'counts': counts, 'pages': pages});

  // ---- 08 搜索 -------------------------------------------------------------

  Future<Object?> searchTag() =>
      _get(DomainType.apiData, Endpoints.searchTag);

  Future<Object?> search(String type, {
    required String keywords,
    int sort = 1,
    int pages = 1,
    int counts = 20,
  }) =>
      _get(DomainType.apiData, Endpoints.search(type), query: {
        'keywords': keywords,
        'sort': sort,
        'pages': pages,
        'counts': counts,
      });

  Future<Object?> searchData(String type, {
    required String keywords,
    int sort = 1,
    int pages = 1,
    int counts = 20,
  }) =>
      _get(DomainType.apiData, Endpoints.searchData(type), query: {
        'keywords': keywords,
        'sort': sort,
        'pages': pages,
        'counts': counts,
      });

  Future<Object?> searchNs(String type, {
    required String keywords,
    int sort = 1,
    int pages = 1,
    int counts = 20,
  }) =>
      _get(DomainType.apiData, Endpoints.searchNs(type), query: {
        'keywords': keywords,
        'sort': sort,
        'pages': pages,
        'counts': counts,
      });

  // ---- 09 首页 / 榜单 / 推荐 / 分类 ---------------------------------------

  Future<Object?> comicBanner({int type = 1, int platform = 1}) =>
      _get(DomainType.apiData, Endpoints.comicBanner,
          query: {'type': type, 'platform': platform});

  Future<Object?> comicNew({String source = 'ns', int type = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData,
          source == 'av' ? Endpoints.comicDataNew : Endpoints.comicNsNew,
          query: {'type': type, 'counts': counts, 'pages': pages});

  Future<Object?> comicRanking({String source = 'ns', int type = 1, int counts = 20, int pages = 1, int range = 1}) =>
      _get(DomainType.apiData,
          source == 'av' ? Endpoints.comicDataRanking : Endpoints.comicNsRanking,
          query: {'type': type, 'counts': counts, 'pages': pages, 'range': range});

  Future<Object?> comicRecommend({String source = 'ns', int type = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData,
          source == 'av' ? Endpoints.comicDataRecommend : Endpoints.comicNsRecommend,
          query: {'type': type, 'counts': counts, 'pages': pages});

  Future<Object?> comicNsCategory({int type = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData, Endpoints.comicNsCategory,
          query: {'type': type, 'counts': counts, 'pages': pages});

  Future<Object?> animatNew({int type = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData, Endpoints.nsAnimatNew,
          query: {'type': type, 'counts': counts, 'pages': pages});

  Future<Object?> animatRanking({int type = 1, int counts = 20, int pages = 1, int range = 1}) =>
      _get(DomainType.apiData, Endpoints.nsAnimatRanking,
          query: {'type': type, 'counts': counts, 'pages': pages, 'range': range});

  Future<Object?> animatRecommend({int type = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData, Endpoints.nsAnimatRecommend,
          query: {'type': type, 'counts': counts, 'pages': pages});

  Future<Object?> fictionNew({int type = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData, Endpoints.fictionNew,
          query: {'type': type, 'counts': counts, 'pages': pages});

  Future<Object?> fictionRanking({int type = 1, int counts = 20, int pages = 1, int range = 1}) =>
      _get(DomainType.apiData, Endpoints.fictionRanking,
          query: {'type': type, 'counts': counts, 'pages': pages, 'range': range});

  Future<Object?> fictionRecommend({int type = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData, Endpoints.fictionRecommend,
          query: {'type': type, 'counts': counts, 'pages': pages});

  Future<Object?> photoNew({int type = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData, Endpoints.photoNew,
          query: {'type': type, 'counts': counts, 'pages': pages});

  Future<Object?> photoRanking({int type = 1, int counts = 20, int pages = 1, int range = 1}) =>
      _get(DomainType.apiData, Endpoints.photoRanking,
          query: {'type': type, 'counts': counts, 'pages': pages, 'range': range});

  Future<Object?> photoRecommend({int type = 1, int counts = 20, int pages = 1}) =>
      _get(DomainType.apiData, Endpoints.photoRecommend,
          query: {'type': type, 'counts': counts, 'pages': pages});

  Future<Object?> photoTag() => _get(DomainType.apiData, Endpoints.photoTag);

  Future<Object?> photoSimilar(int id) =>
      _get(DomainType.apiData, Endpoints.photoSimilar, query: {'id': id});

  // ---- 10 详情 ------------------------------------------------------------

  Future<Object?> comicNsDetail(int id) =>
      _get(DomainType.apiData, Endpoints.comicNsInternalId(id));

  Future<Object?> comicAvDetail(int comicId) =>
      _get(DomainType.apiData, Endpoints.comicInternalId(comicId));

  Future<Object?> animatDetail(int id) =>
      _get(DomainType.apiData, Endpoints.animatInternalId(id));

  Future<Object?> nsAnimatDetail(int id) =>
      _get(DomainType.apiData, Endpoints.nsAnimatInternalId(id));

  // ---- 11 阅读 ------------------------------------------------------------

  /// 漫画(ns) 页表。参数名必须 `comic_id`（传 id → 410，见 §9C.3）。
  Future<Object?> comicNsRead({
    required int comicId,
    int counts = 0,
    int pages = 0,
    bool userType = false,
    String? sdb,
  }) =>
      _get(DomainType.apiData, Endpoints.comicNsRead, query: {
        'comic_id': comicId,
        'counts': counts,
        'pages': pages,
        'user_type': userType,
        if (sdb != null) 'sdb': sdb,
      });

  /// 图集页表。
  Future<Object?> photoRead({
    required int id,
    int counts = 0,
    int pages = 0,
  }) =>
      _get(DomainType.apiData, Endpoints.photoRead,
          query: {'id': id, 'counts': counts, 'pages': pages});

  // ---- 12 收藏增删 / 历史增删 --------------------------------------------

  /// 收藏指定内容的路径（按内容种类区分不同的 v3 前缀）。
  ///
  /// **动漫 AV / NS 是两套 id 空间**：NS（`source=='ns'`）必须走 `v3/nsanimat/favorite`，
  /// 否则会写到 AV 的收藏里（同名 id 还可能串号）→ 表现为「收藏有概率无效」。
  String _favoritePath(String kind, int id, [String? source]) {
    switch (kind) {
      case 'animat':
        return source == 'ns'
            ? Endpoints.nsAnimatFavoriteId(id)
            : Endpoints.animatFavoriteId(id);
      case 'comicNs':
        return Endpoints.comicNsFavoriteId(id);
      case 'comicAv':
        return Endpoints.comicDataFavoriteId(id);
      case 'fiction':
        return Endpoints.fictionFavoriteId(id);
      default:
        return Endpoints.collectFavorite(kind);
    }
  }

  String _favoriteBase(String kind, [String? source]) {
    switch (kind) {
      case 'animat':
        // AV → v2/animat/favorite；NS → v3/nsanimat/favorite。
        return source == 'ns'
            ? Endpoints.nsAnimatFavorite
            : Endpoints.animatFavorite;
      case 'comicNs':
        return Endpoints.comicNsFavorite;
      case 'comicAv':
        return Endpoints.comicDataFavorite;
      default:
        return Endpoints.collectFavorite(kind);
    }
  }

  String _historyBase(String kind) {
    switch (kind) {
      case 'comicNs':
        return Endpoints.comicNsHistory;
      case 'comicAv':
        return Endpoints.comicDataHistory;
      default:
        return Endpoints.collectHistory(kind);
    }
  }

  String _historyPath(String kind, int id) {
    switch (kind) {
      case 'comicNs':
        return Endpoints.comicNsHistoryId(id);
      case 'comicAv':
        return Endpoints.comicDataHistoryId(id);
      case 'fiction':
        return Endpoints.fictionHistoryId(id);
      case 'animat':
      default:
        return Endpoints.animatHistoryId(id);
    }
  }

  Future<Object?> addFavorite(String kind, int id, {String? source}) =>
      _put(DomainType.apiData, _favoritePath(kind, id, source));

  Future<Object?> removeFavorite(String kind, List<int> ids, {String? source}) =>
      _delete(
        DomainType.apiData,
        _favoriteBase(kind, source),
        query: {'ids': ids.join(',')},
      );

  Future<Object?> clearFavorite(String kind) =>
      _delete(DomainType.apiData, '${_favoriteBase(kind)}All');

  /// 写观看/阅读进度。
  /// - 动画：无体。
  /// - 小说：`percent`（0..1）。
  /// - 漫画(ns/av)：`last_page`。
  Future<Object?> writeHistory(
    String kind,
    int id, {
    int? lastPage,
    double? percent,
  }) {
    final query = <String, dynamic>{};
    if (lastPage != null) query['last_page'] = lastPage;
    if (percent != null) query['percent'] = percent;
    return _put(DomainType.apiData, _historyPath(kind, id),
        query: query.isEmpty ? null : query);
  }

  Future<Object?> deleteHistory(String kind, List<int> ids) => _delete(
        DomainType.apiData,
        _historyBase(kind),
        query: {'ids': ids.join(',')},
      );
}

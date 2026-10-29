import 'package:shared_preferences/shared_preferences.dart';

/// 域名类型（com/manmanlu2/model/type/DomainType）。
enum DomainType {
  apiData('api_url_data', 'api'),
  apiComic('api_url_comic', 'comic'),
  apiFiction('api_url_fiction', 'fiction'),
  apiImg('api_url_img', 'img'),
  apiStream('api_url_stream', 'stream');

  const DomainType(this.value, this.headerValue);
  final String value;
  final String headerValue;
}

/// 运行时域名存储。
///
/// 对应 BaseDomain（Lg/n/l/a/p/a;）静态字段 + Koin 属性表。
/// 启动测速成功后由 [apply] 写入；缺省使用静态默认值。
class DomainStore {
  DomainStore(this._prefs);

  final SharedPreferences _prefs;

  /// BaseDomain 静态默认值（取沙箱实测可达线路，host.txt 可覆盖）。
  static const Map<DomainType, String> _defaults = {
    DomainType.apiData: 'https://api1.mmlu.services',
    DomainType.apiComic: 'https://ac1.mmlutech.xyz',
    DomainType.apiFiction: 'https://fiction1.mmlutech.xyz',
    DomainType.apiImg: 'https://img1.mmlutech.xyz',
    DomainType.apiStream: 'https://api1.mmlu.services',
  };

  /// 漫画/图片 CDN 的 referer（BaseDomain.e / h），运行时填充。
  String get comicReferer => _prefs.getString('domain_comic_referer') ?? '';
  String get imgReferer => _prefs.getString('domain_img_referer') ?? '';

  /// 流媒体线路：拉 m3u8 用的 API 域、`?host=` 用的 CDN 主机、chain 串。
  /// 默认取沙箱实测可用值（docs/PROTOCOL.md §9B.1）：`?host=` 用 `na.mmlu1.site`
  /// （host.txt 下发的 `stream-encrypt1.*` 对 AV 密钥/分片会 403，见 StreamService）。
  String get streamFetchUrl =>
      _prefs.getString('stream_fetch_url') ?? 'https://api1.mmlu.services';
  String get streamTsUrl =>
      _prefs.getString('stream_ts_url') ?? 'na.mmlu1.site';
  String get streamChain =>
      _prefs.getString('stream_chain') ?? 'miOBGgHNWhpt2';

  Future<void> setStreamLine({
    required String fetchUrl,
    required String tsUrl,
    required String chain,
  }) async {
    await _prefs.setString('stream_fetch_url', fetchUrl);
    await _prefs.setString('stream_ts_url', tsUrl);
    await _prefs.setString('stream_chain', chain);
  }

  String urlOf(DomainType t) =>
      _prefs.getString(t.value) ?? _defaults[t] ?? '';

  /// 写入某类型域名（对应 C1(DomainType, value) -> k.s1(type.getValue(), url)）。
  Future<void> set(DomainType t, String url) => _prefs.setString(t.value, url);

  /// 对应 Lg/n/b/n/p2;->a(...)：一次性应用 5 类域名与辅参。
  Future<void> apply({
    required String api,
    required String comic,
    required String fiction,
    required String img,
    required String stream,
    String comicReferer = '',
    String imgReferer = '',
    String streamHostUrl = '',
    String streamChain = '',
    String streamCc = '',
  }) async {
    await set(DomainType.apiData, api);
    await set(DomainType.apiComic, comic);
    await set(DomainType.apiFiction, fiction);
    await set(DomainType.apiImg, img);
    await set(DomainType.apiStream, stream);
    if (comicReferer.isNotEmpty) {
      await _prefs.setString('domain_comic_referer', comicReferer);
    }
    final ir = imgReferer.isNotEmpty ? imgReferer : streamHostUrl;
    if (ir.isNotEmpty) await _prefs.setString('domain_img_referer', ir);
    if (stream.isNotEmpty) {
      await setStreamLine(
        fetchUrl: stream,
        tsUrl: streamHostUrl.isNotEmpty ? streamHostUrl : streamTsUrl,
        chain: streamChain.isNotEmpty ? streamChain : this.streamChain,
      );
    }
  }
}

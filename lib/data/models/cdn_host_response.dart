/// 测速候选域名 (DomainTestBean)。
class DomainTestBean {
  DomainTestBean({
    this.url,
    this.hostUrl,
    this.chain,
    this.cc,
    this.referer,
    this.isValid = true,
  });

  final String? url;
  final String? hostUrl;
  final String? chain;
  final String? cc;
  final String? referer;
  final bool isValid;

  factory DomainTestBean.fromJson(Map<String, dynamic> j) => DomainTestBean(
        url: j['url'] as String?,
        hostUrl: j['hostUrl'] as String? ?? j['host_url'] as String?,
        chain: j['chain'] as String?,
        cc: j['cc'] as String?,
        referer: j['referer'] as String?,
        isValid: j['isValid'] as bool? ?? true,
      );
}

/// CDN 域名列表响应 (CdnHostResponse)。
class CdnHostResponse {
  CdnHostResponse({
    this.api,
    this.comic,
    this.fiction,
    this.img,
    this.stream,
  });

  final List<DomainTestBean>? api;
  final List<DomainTestBean>? comic;
  final List<DomainTestBean>? fiction;
  final List<DomainTestBean>? img;
  final List<DomainTestBean>? stream;

  factory CdnHostResponse.fromJson(Map<String, dynamic> j) => CdnHostResponse(
        api: _list(j['api']),
        comic: _list(j['comic']),
        fiction: _list(j['fiction']),
        img: _list(j['img']),
        stream: _list(j['stream']),
      );

  static List<DomainTestBean>? _list(Object? o) => (o is List)
      ? o
          .whereType<Map>()
          .map((e) => DomainTestBean.fromJson(e.cast<String, dynamic>()))
          .toList()
      : null;
}

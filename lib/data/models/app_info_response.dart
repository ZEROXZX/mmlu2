/// 应用信息 (AppInfoResponse)。
///
/// 注意：响应**无统一信封**（无 code/message），body 顶层即数据。
/// 这里只声明骨架模型所需字段，其余按需扩展。
class AppInfoResponse {
  AppInfoResponse({
    this.id,
    this.ad,
    this.android,
    this.categoryList,
    this.chatGroup,
    this.floatBtnGroup,
    this.newsUrl,
    this.prompt,
    this.share,
    this.system,
  });

  final int? id;
  final Map<String, dynamic>? ad;
  final Map<String, dynamic>? android;

  /// JSON 字段 `category_list`。
  final List<dynamic>? categoryList;
  final Map<String, dynamic>? chatGroup;
  final Map<String, dynamic>? floatBtnGroup;
  final String? newsUrl;
  final Map<String, dynamic>? prompt;
  final Map<String, dynamic>? share;
  final SystemGson? system;

  factory AppInfoResponse.fromJson(Map<String, dynamic> j) => AppInfoResponse(
        id: j['_id'] as int? ?? j['id'] as int?,
        ad: j['ad'] as Map<String, dynamic>?,
        android: j['android'] as Map<String, dynamic>?,
        categoryList: j['category_list'] as List<dynamic>?,
        chatGroup: j['chatGroup'] as Map<String, dynamic>?,
        floatBtnGroup: j['floatBtnGroup'] as Map<String, dynamic>?,
        newsUrl: j['newsUrl'] as String?,
        prompt: j['prompt'] as Map<String, dynamic>?,
        share: j['share'] as Map<String, dynamic>?,
        system: j['system'] is Map<String, dynamic>
            ? SystemGson.fromJson(j['system'] as Map<String, dynamic>)
            : null,
      );
}

/// SystemGson：全站免费开关。
class SystemGson {
  SystemGson({this.isFree, this.isFreeMessage});

  final bool? isFree;
  final String? isFreeMessage;

  factory SystemGson.fromJson(Map<String, dynamic> j) => SystemGson(
        isFree: _asBool(j['is_free']),
        isFreeMessage: j['is_free_message'] as String?,
      );

  static bool? _asBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return null;
  }
}

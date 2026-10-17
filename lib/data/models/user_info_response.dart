/// 用户信息 (UserInfoResponse)。
/// 字段来源：dex UserInfoResponse + MemberBean。
class UserInfoResponse {
  UserInfoResponse({
    this.id,
    this.phone,
    this.countryCodes,
    this.level,
    this.levelExpiryAt,
    this.lock,
  });

  final int? id;
  final String? phone;

  /// JSON 字段 `country_codes`。
  final String? countryCodes;

  /// 会员等级；> 1 视为 VIP（见 MemberModel.isVip）。
  final int? level;
  final int? levelExpiryAt;
  final int? lock;

  factory UserInfoResponse.fromJson(Map<String, dynamic> j) => UserInfoResponse(
        id: _asInt(j['id']),
        phone: j['phone'] as String?,
        countryCodes: j['country_codes'] as String?,
        level: _asInt(j['level']),
        levelExpiryAt: _asInt(j['level_expiry_at']),
        lock: _asInt(j['lock']),
      );

  bool get isVip => (level ?? 0) > 1;

  static int? _asInt(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
}

/// 会员 bean (MemberBean)。
class MemberBean {
  MemberBean({
    this.id,
    this.countryCode,
    this.mobile,
    this.level,
    this.levelExpiryAt,
    this.lockStamp,
  });

  final String? id;
  final String? countryCode;
  final String? mobile;
  final int? level;
  final int? levelExpiryAt;
  final int? lockStamp;

  factory MemberBean.fromJson(Map<String, dynamic> j) => MemberBean(
        id: j['_id'] as String? ?? j['id'] as String?,
        countryCode: j['countryCode'] as String?,
        mobile: j['mobile'] as String?,
        level: j['level'] as int?,
        levelExpiryAt: j['levelExpiryAt'] as int?,
        lockStamp: j['lockStamp'] as int?,
      );

  bool get isVip => (level ?? 0) > 1;
}

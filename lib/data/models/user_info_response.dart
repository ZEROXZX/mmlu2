/// 用户信息 (UserInfoResponse)。
/// 字段来源：dex UserInfoResponse + MemberBean。
///
/// ⚠ 服务端字段类型不稳定（如 `phone` 可能是 int），一律用 [_str] 宽松取字符串，
/// 数值字段用 [_intv]，避免运行时 `type cast` 崩溃。
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
        id: _intv(j['id']),
        phone: _str(j['phone']),
        countryCodes: _str(j['country_codes']),
        level: _intv(j['level']),
        levelExpiryAt: _intv(j['level_expiry_at']),
        lock: _intv(j['lock']),
      );

  bool get isVip => (level ?? 0) > 1;
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
        id: _str(j['_id'] ?? j['id']),
        countryCode: _str(j['countryCode']),
        mobile: _str(j['mobile']),
        level: _intv(j['level']),
        levelExpiryAt: _intv(j['levelExpiryAt']),
        lockStamp: _intv(j['lockStamp']),
      );

  bool get isVip => (level ?? 0) > 1;
}

String? _str(Object? v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

int? _intv(Object? v) => v is int
    ? v
    : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));

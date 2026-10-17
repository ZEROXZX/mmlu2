/// 登录/注册返回 (com/manmanlu2/model/response/TokenResponse，classDefIdx 915)。
///
/// ⚠ 服务端字段类型不稳定：`UUID` / `userId` 可能是 **int** 也可能是字符串，
/// 一律用宽松转换（[_str]）取，避免 `type 'int' is not a subtype of type
/// 'String?' in type cast`。
class TokenResponse {
  TokenResponse({this.uuid, this.token, this.userId});

  final String? uuid;
  final String? token;
  final String? userId;

  factory TokenResponse.fromJson(Map<String, dynamic> j) => TokenResponse(
        uuid: _str(j['UUID'] ?? j['uuid']),
        token: _str(j['token']),
        userId: _str(j['userId'] ?? j['user_id']),
      );

  Map<String, dynamic> toJson() =>
      {'UUID': uuid, 'token': token, 'userId': userId};

  static String? _str(Object? v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }
}

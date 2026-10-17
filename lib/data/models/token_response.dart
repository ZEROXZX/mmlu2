/// 登录/注册返回 (com/manmanlu2/model/response/TokenResponse，classDefIdx 915)。
class TokenResponse {
  TokenResponse({this.uuid, this.token, this.userId});

  final String? uuid;
  final String? token;
  final String? userId;

  factory TokenResponse.fromJson(Map<String, dynamic> j) => TokenResponse(
        uuid: j['UUID'] as String? ?? j['uuid'] as String?,
        token: j['token'] as String?,
        userId: j['userId'] as String? ?? j['user_id'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'UUID': uuid, 'token': token, 'userId': userId};
}

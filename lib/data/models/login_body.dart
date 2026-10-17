/// 登录请求体，对应 Lcom/manmanlu2/model/body/LoginBody;
/// （Kotlin data class，sourceFile LoginBody.kt，classDefIdx 866）。
///
/// 构造参数顺序（smali <init> @5083332，逐条 iput 确认）：
///   (countryCode, mobile, pwd, platform)
/// Gson 字段键名来自字段上的 @SerializedName（smali_export 确认）：
///   countryCode -> "country_codes"
///   mobile      -> "phone"
///   pwd         -> "password"
///   platform    -> "platform"
///
/// platform 固定为 2：构造点 Lg/n/b/j/n0/y0;->invoke()
///   传入 `const/4 v5, #0x2`（mid 46637）。
/// 密码为明文直传：LoginPresenter f0() 直接 `iput-object pwd -> q0.e`，
/// 全程无 MD5/加密；RuleUtility 仅做格式校验。
class LoginBody {
  LoginBody({
    required this.countryCodes,
    required this.phone,
    required this.password,
    this.platform = 2,
  });

  final String countryCodes;
  final String phone;
  final String password;
  final int platform;

  Map<String, dynamic> toJson() => {
        'country_codes': countryCodes,
        'phone': phone,
        'password': password,
        'platform': platform,
      };
}

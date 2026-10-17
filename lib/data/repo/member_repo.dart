import 'dart:math';

import '../../core/auth/token_store.dart';
import '../api/api_service.dart';
import '../models/login_body.dart';
import '../models/token_response.dart';
import '../models/user_info_response.dart';

/// 用户/会员仓库。
///
/// 登录引导流程（沙箱实测）：
///   1) 首次运行无 token -> `v2/register` 设备注册，拿到**游客 token** 并存储；
///   2) 带 `Authorization: Bearer <游客token>` 调 `v2/user/login`；
///   3) 用返回的**账号 token** 覆盖存储，此后所有请求均带该 token。
class MemberRepo {
  MemberRepo(this._api, this._tokenStore);

  final ApiService _api;
  final TokenStore _tokenStore;

  TokenStore get tokenStore => _tokenStore;

  /// 确保存在一个 token（游客或账号）；无则先做设备注册。
  Future<String> ensureToken() async {
    final existing = _tokenStore.token;
    if (existing != null) return existing;
    final res = await registerDevice();
    final t = res.token;
    if (t == null) throw StateError('设备注册未返回 token');
    await _tokenStore.save(t);
    return t;
  }

  /// 设备引导注册（游客），返回并存储游客 token。
  Future<TokenResponse> registerDevice({
    String? universalId,
    String model = 'Google_sdk_gphone64_arm64',
  }) async {
    final res = await _api.registerDevice(
      universalId: universalId ?? _uuidV4(),
      model: model,
    );
    if (res.token != null) await _tokenStore.save(res.token!);
    return res;
  }

  /// 登录：先确保游客 token，再登录并持久化账号 token。
  Future<TokenResponse> login({
    required String phone,
    required String password,
    String countryCodes = '86',
  }) async {
    await ensureToken();
    final res = await _api.login(LoginBody(
      countryCodes: countryCodes,
      phone: phone,
      password: password,
    ));
    if (res.token != null) await _tokenStore.save(res.token!);
    return res;
  }

  Future<UserInfoResponse> userInfo() => _api.userInfo();

  Future<bool> isVip() async => (await _api.userInfo()).isVip;

  /// 登出（清除本地 token）。
  Future<void> logout() => _tokenStore.clear();

  /// **官方账号登出**：清除当前账号 token，并重新注册游客 token，
  /// 使 App 回到「已引导但未登录」状态（可继续浏览列表、需登录才能看内容）。
  ///
  /// ⚠ 协议中**没有**服务端 logout 端点（111 接口无 `user/logout`），
  /// 因此登出为纯本地行为：丢弃账号 token 即失效。
  Future<void> officialLogout() async {
    await _tokenStore.clear();
    await registerDevice();
  }

  // ---- 工具 -------------------------------------------------------------

  static final Random _rnd = Random.secure();

  /// RFC 4122 v4 UUID。
  static String _uuidV4() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

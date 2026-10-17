import 'package:dio/dio.dart';

import '../auth/token_store.dart';
import '../constants/mmlu_keys.dart';
import '../crypto/mmlu_crypto.dart';
import '../domain/domain_store.dart';
import '../domain/endpoints.dart';
import 'api_exception.dart';
import 'decrypt_interceptor.dart';
import 'header_interceptor.dart';
import 'sign_interceptor.dart';

/// 鉴权拦截器：为需要鉴权的请求注入 `Authorization: Bearer <token>`。
///
/// 服务端强制 JWT 风格校验：缺 token -> HTTP 499「缺少 Token 參數」；
/// 非法/格式错 -> HTTP 498「Token 格式錯誤」（沙箱实测）。
/// token 本身由 `v2/register`（游客）或 `v2/user/login`（账号）签发，
/// 形如 `base64(payload).md5hex.randomhex`；注入时必须加 `Bearer ` 前缀。
/// 通过 `options.extra['noAuth'] = true` 可跳过；请求已带 Authorization 则不覆盖。
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokenStore);

  final TokenStore _tokenStore;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final noAuth = options.extra['noAuth'] == true;
    final existing = options.headers[MmluConstants.authorizationHeader];
    if (!noAuth && (existing == null || (existing is String && existing.isEmpty))) {
      final t = _tokenStore.token;
      if (t != null) {
        options.headers[MmluConstants.authorizationHeader] =
            '${MmluConstants.authScheme} $t';
      }
    }
    handler.next(options);
  }
}

/// 将 HTTP 非 2xx 或缺 token 等错误统一转换为 [ApiException]。
class ApiErrorInterceptor extends Interceptor {
  ApiErrorInterceptor(this.apiKey);

  final String apiKey;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final code = response.statusCode ?? 0;
    if (code >= 400) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: _message(response),
        ),
        true,
      );
      return;
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final res = err.response;
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: res,
        type: err.type,
        error: ApiException(
          res?.statusCode ?? -1,
          _message(res) ?? err.message ?? 'network error',
          body: res?.data,
        ),
        message: err.message,
      ),
      true,
    );
  }

  String? _message(Response? res) {
    if (res == null) return null;
    final d = res.data;
    // 统一走 extractApiMessage：兼容 {error:".."} / {error:{message:".."}} /
    // {message:".."} 等信封，避免 Map 型 error 被漏掉退化成 network error。
    final msg = extractApiMessage(d);
    if (msg.isNotEmpty) return msg;
    if (d is String) return d.length > 300 ? '${d.substring(0, 300)}…' : d;
    return null;
  }
}

/// 网络客户端：OkHttp(30s) + 拦截器链的 Dio 等价实现。
///
/// 拦截器顺序与 App 保持一致：
///   HeaderInterceptor -> (AuthInterceptor) -> SignInterceptor -> DecryptInterceptor
class ApiClient {
  ApiClient({
    required this.tokenStore,
    required this.domainStore,
    String? apiKey,
    String? secureKey,
  })  : apiKey = apiKey ?? MmluKeys.apiKey,
        secureKey = secureKey ?? MmluKeys.secureKey {
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      validateStatus: (s) => s != null,
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
    ));
    dio.interceptors.addAll([
      const HeaderInterceptor(),
      AuthInterceptor(tokenStore),
      SignInterceptor(this.secureKey),
      DecryptInterceptor(this.apiKey),
      ApiErrorInterceptor(this.apiKey),
    ]);
  }

  final TokenStore tokenStore;
  final DomainStore domainStore;
  final String apiKey;
  final String secureKey;
  late final Dio dio;

  Future<void>? _registering;

  /// 游客 token 是否存在。
  bool get hasToken {
    final t = tokenStore.token;
    return t != null && t.isNotEmpty;
  }

  /// 确保存在一个 token：无（或 [force]）时做一次 `v2/register` 设备注册，
  /// 拿到游客 token 并存储。并发调用共享同一次请求。
  ///
  /// 对应参考实现 `register()`：启动即注册，使内容接口不再因缺
  /// `Authorization` 而返回 499「缺少 Token 参数」。
  Future<void> ensureGuestToken({bool force = false}) {
    if (!force && hasToken) return Future<void>.value();
    return _registering ??= _doRegister().whenComplete(() {
      _registering = null;
    });
  }

  Future<void> _doRegister() async {
    final uid = tokenStore.universalId;
    final body = <String, dynamic>{
      'universal_id': uid,
      'platform': 2,
      'model': 'SM-G975F',
      'key': MmluCrypto.sha256Hex('hcg${uid}hcg'),
      'install_channel': 'com.android.vending',
      'install': '',
      'source': '',
    };
    final base = domainStore.urlOf(DomainType.apiData);
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    try {
      final r = await dio.post(
        '$root/${Endpoints.register}',
        data: body,
        options: Options(extra: {'noAuth': true}),
      );
      final data = r.data;
      String? token;
      if (data is Map) {
        final inner = data['data'] is Map
            ? (data['data'] as Map).cast<String, dynamic>()
            : data.cast<String, dynamic>();
        token = inner['token']?.toString();
      }
      if (token != null && token.isNotEmpty) {
        await tokenStore.save(token);
        // 注册后必须调一次 startup 激活会话，否则内容接口返回
        // `{"error":{"msg":"unidentify"}}`（参考实现 register() 内同样调用）。
        try {
          await dio.get('$root/${Endpoints.startup}',
              queryParameters: {'platform': 2});
        } catch (_) {}
      }
    } on DioException catch (e) {
      throw ApiException(
        e.response?.statusCode ?? -1,
        '游客注册失败: ${e.message}',
        body: e.response?.data,
      );
    }
  }

  /// 解析并按需解密 host.txt，返回明文 JSON 字符串。
  Future<String> fetchAndDecryptHostTxt() async {
    DioException? last;
    for (final url in MmluKeys.hostTxtUrls) {
      try {
        final res = await Dio().get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        final body = (res.data ?? '').trim();
        if (body.isEmpty) continue;
        return MmluCrypto.decryptHost(
          hostKey: MmluKeys.hostKey,
          hostIv: MmluKeys.hostIv,
          bodyBase64: body,
        );
      } on DioException catch (e) {
        last = e;
      }
    }
    throw ApiException(-1, 'host.txt 拉取失败: ${last?.message}');
  }
}

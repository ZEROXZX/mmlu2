import 'package:dio/dio.dart';

import '../constants/mmlu_keys.dart';
import '../crypto/mmlu_crypto.dart';

/// 对应 RequestInterceptor (Lg/n/l/a/r/b;，code_off 5253124)。
///
/// 生成 nonce 并计算 `payload` / `ebody` 头；注意 **不修改请求 body**
/// （业务参数仍以明文 JSON 发送）。
class SignInterceptor extends Interceptor {
  SignInterceptor(this.secureKey, {String Function()? nonceProvider})
      : nonceProvider = nonceProvider ?? MmluCrypto.newNonce;

  final String secureKey;

  /// nonce 生成器；测试时可注入固定值。
  final String Function() nonceProvider;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final nonce = nonceProvider();
    // path = request.url.encodedPath.substring(1)
    var path = options.uri.path;
    if (path.startsWith('/')) path = path.substring(1);
    final ebody = MmluCrypto.buildEbody(
      secureKey: secureKey,
      path: path,
      nonce: nonce,
    );
    options.headers[MmluConstants.payloadHeader] = nonce;
    options.headers[MmluConstants.ebodyHeader] = ebody;
    handler.next(options);
  }
}

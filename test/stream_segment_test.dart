import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/core/auth/token_store.dart';
import 'package:mmlu_client/core/crypto/mmlu_crypto.dart';
import 'package:mmlu_client/core/domain/domain_store.dart';
import 'package:mmlu_client/data/service/stream_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 固定返回同一段字节的假适配器，避免真实网络。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.bytes);

  final List<int> bytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(bytes, 200);

  @override
  void close({bool force = false}) {}
}

late SharedPreferences _prefs;

StreamService _svcWith(List<int> bytes) {
  final dio = Dio()..httpClientAdapter = _StubAdapter(bytes);
  return StreamService(
    domains: DomainStore(_prefs),
    tokenStore: TokenStore(_prefs),
    dio: dio,
  );
}

/// 锁定代理/下载共用的「明文流」契约：m3u8 无 `#EXT-X-KEY` 时 key 为 null，
/// 分片必须原样返回，不能因为缺 key 抛错（否则代理返回 500、播放失败）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  test('fetchSegment: key 为 null 时原样返回分片字节', () async {
    final raw = [1, 2, 3, 4, 5, 6, 7, 8];
    final out = await _svcWith(raw).fetchSegment('http://x/s.ts', null, null);
    expect(out, raw);
  });

  test('fetchSegment: 空 key 同样按明文处理', () async {
    final out = await _svcWith([9, 9, 9]).fetchSegment(
      'http://x/s.ts',
      Uint8List(0),
      null,
    );
    expect(out, [9, 9, 9]);
  });

  test('fetchSegment: 有 key 时正常 AES-128-CBC 解密', () async {
    final key = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final iv = Uint8List.fromList(List<int>.generate(16, (i) => 255 - i));
    final plain = Uint8List.fromList(List<int>.generate(32, (i) => i * 3 % 256));
    final ct = MmluCrypto.aesCbcEncrypt(key, iv, plain);
    final out = await _svcWith(ct).fetchSegment('http://x/s.ts', key, iv);
    expect(out, plain);
  });
}

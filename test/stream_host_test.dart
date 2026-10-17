import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/core/auth/token_store.dart';
import 'package:mmlu_client/core/domain/domain_store.dart';
import 'package:mmlu_client/data/service/stream_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 锁定 AV 动漫 `?host=` 归一化契约：host.txt 的 `stream-encrypt1.*` 会让
/// key.php/.ts 一律 403，必须改用 `na.mmlu1.site`（NS 端点亦忽略 host）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    svc = StreamService(domains: DomainStore(prefs), tokenStore: TokenStore(prefs));
  });

  String hostOf(String url) =>
      RegExp(r'[?&]host=([^&]+)').firstMatch(url)!.group(1)!;

  test('默认线路 stream-encrypt1（host.txt tsurl）被归一化为 na.mmlu1.site', () {
    final url = svc.buildM3u8Url('/v1/animat/media/720/GHOSTFATHER-0008.m3u8');
    expect(hostOf(url), 'na.mmlu1.site');
    expect(url, startsWith('https://api1.mmlu.services/v1/animat/media/720/'));
    expect(url, contains('chain=miOBGgHNWhpt2'));
  });

  test('显式传入 stream-encrypt 主机同样被归一化', () {
    final url = svc.buildM3u8Url('/x.m3u8',
        host: 'https://stream-encrypt1.mmlu4.site');
    expect(hostOf(url), 'na.mmlu1.site');
  });

  test('空/缺失主机回退 na.mmlu1.site', () {
    expect(hostOf(svc.buildM3u8Url('/x.m3u8', host: '')), 'na.mmlu1.site');
    expect(hostOf(svc.buildM3u8Url('/x.m3u8', host: 'https://')), 'na.mmlu1.site');
  });

  test('其它可用主机保持原样', () {
    expect(hostOf(svc.buildM3u8Url('/x.m3u8', host: 'https://na.mmlu1.site/')),
        'na.mmlu1.site');
    expect(hostOf(svc.buildM3u8Url('/x.m3u8', host: 'my.cdn.example')),
        'my.cdn.example');
  });
}

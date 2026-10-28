import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/core/network/http_factory.dart';

void main() {
  tearDown(() {
    HttpFactory.setProxy(null);
    HttpFactory.setAllowBadCert(false);
  });

  test('空代理 = 直连', () {
    HttpFactory.setProxy('');
    expect(HttpFactory.proxy, isNull);
    expect(HttpFactory.describe(), '直连');
    expect(HttpFactory.findProxyFor(Uri.parse('https://a.b')), 'DIRECT');
  });

  test('http:// 代理正确转换 findProxy', () {
    HttpFactory.setProxy('http://127.0.0.1:7890');
    expect(HttpFactory.describe(), '代理 http://127.0.0.1:7890');
    expect(HttpFactory.findProxyFor(Uri.parse('https://api1.mmlu.services')),
        'PROXY 127.0.0.1:7890');
  });

  test('裸 host:port 显式端口', () {
    HttpFactory.setProxy('127.0.0.1:1080');
    expect(HttpFactory.findProxyFor(Uri.parse('https://x')),
        'PROXY 127.0.0.1:1080');
  });

  test('允许不安全证书开关生效', () {
    HttpFactory.setAllowBadCert(true);
    expect(HttpFactory.allowBadCert, isTrue);
    HttpFactory.setAllowBadCert(false);
    expect(HttpFactory.allowBadCert, isFalse);
  });
}

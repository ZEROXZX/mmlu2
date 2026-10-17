import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/core/crypto/mmlu_crypto.dart';

/// 金标向量由 OpenSSL 3.0.13 生成（openssl enc -aes-256-cbc -nosalt），
/// 用于锁定 crypto 实现的字节级正确性。
void main() {
  group('MD5 家族', () {
    test('md5HexZp = 补零小写 hex', () {
      expect(MmluCrypto.md5HexZp('1234567890'),
          'e807f1fcf82d132f9bb018ca6738a19f');
    });

    test('md5HexBigInt = 不补零小写 hex', () {
      // 同一输入下与 md5HexZp 值一致（该向量恰好无前导零）
      expect(MmluCrypto.md5HexBigInt(utf8.encode('1234567890')),
          'e807f1fcf82d132f9bb018ca6738a19f');
    });

    test('g2 = substring(8,24)', () {
      expect(MmluCrypto.g2('1234567890'), 'f82d132f9bb018ca');
      expect(MmluCrypto.g2('1234567890').length, 16);
    });
  });

  group('ebody 加密（请求签名）', () {
    test('与 OpenSSL 金标一致', () {
      const secureKey = 'OlFXpWEoON2n+EuUuvDOod5lauDh98GLYmCsvBgMwts=';
      final ebody = MmluCrypto.buildEbody(
        secureKey: secureKey,
        path: 'v2/user/login',
        nonce: '1234567890',
      );
      expect(
        ebody,
        'QJ1hZaedy8U/CWJA685SPc8ZlTV1K/rZ/imC0j2PEeHYNI6/Lb+fzinE5gq9qDEIwpTU51gfRJnil56H7MzTyg==',
      );
    });
  });

  group('响应解密', () {
    test('与 OpenSSL 金标一致', () {
      final plain = MmluCrypto.decryptResponse(
        apiKey: '6e561ccd4aade2fed458d4da61e76770',
        xResponseLength: '1234567890',
        bodyBase64:
            '01x7eQfr7cULu83bceI/JAMFo4S7hqM6bboeZTcuXjc2M8hqXqci84Z8sMmgtv1a',
      );
      expect(plain, '{"_id":1,"system":{"is_free":true}}');
    });
  });

  group('host.txt 解密', () {
    test('解密后 substring(32, len-32)', () {
      final out = MmluCrypto.decryptHost(
        hostKey: 'Kp0YhE24edXfJySdI4U/naedvDbWvXQKAlUp5zpVCh4=',
        hostIv: 'TNzGV5P8ikpnNZOnK5Z3XA==',
        bodyBase64:
            '8OI790wpyC566+IPaCqG75eGYp5l6iT+AIpij1PaIs+YvvAmRpED1SZ6dOUVohFF1E4vNOV0/YupcxjLziGGLgXDMutNpXSv+GEEfN2MLVjfcIdOwaXVzGORhl/VBp5vhZbe9kt3fqIukgN/yp3e0Q==',
      );
      expect(out, '{"api":"https://api1.mmlu.services"}');
    });
  });

  group('SHA-256（设备注册 key）', () {
    test('sha256Hex 标准向量', () {
      // sha256("abc")
      expect(MmluCrypto.sha256Hex('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(MmluCrypto.sha256Hex('abc').length, 64);
    });

    test('设备注册 key = sha256Hex("hcg"+universalId+"hcg")', () {
      const id = '94c2a232-4c23-4576-bff8-1f6bf60a45cc';
      final key = MmluCrypto.sha256Hex('hcg${id}hcg');
      expect(key.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
    });
  });

  test('nonce 为 10 位数字串', () {
    for (var i = 0; i < 50; i++) {
      final n = MmluCrypto.newNonce();
      expect(n.length, 10);
      expect(int.tryParse(n), isNotNull);
    }
  });
}

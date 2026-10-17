/// 由 libcipher-lib.so 解出的固定密钥常量。
///
/// 源码：CipherClient（net.idik.lib.cipher.so.CipherClient）。
/// 解密链：CipherCore.getString(hexKey) -> map[hexKey] base64 -> AES("mmluSecretKey", iv=0) 明文。
class MmluKeys {
  MmluKeys._();

  static const String apiKey = '6e561ccd4aade2fed458d4da61e76770';
  static const String appKey = 'uh4S4k3AYe1LqViQuMgeWntH8L0=';
  static const String apiEncryptHeaderKey =
      'qv5ntw2zk3V4dUMZ8fLX/Rd9n40dz+Gos4U2DXOv7to=';
  static const String secureKey =
      'OlFXpWEoON2n+EuUuvDOod5lauDh98GLYmCsvBgMwts=';
  static const String hostKey =
      'Kp0YhE24edXfJySdI4U/naedvDbWvXQKAlUp5zpVCh4=';
  static const String hostIv = 'TNzGV5P8ikpnNZOnK5Z3XA==';

  static const String comicDecryptKey = 'C2A830A5E687678418F88F652984E925';
  static const String comicDecryptIV = '958DB2E92B361F373BFB35CCCC296FBB';
  static const String imgDecryptKey = 'B2F3842866F9583D1ECE61C4E055C255';
  static const String imgDecryptIV = 'E01EDE6331D37AFCC7BE05597D654D22';
  static const String nsAnimeImageDecryptKey =
      '204149A15B092E24E89CEB31040148DB';
  static const String nsAnimeImageDecryptIv =
      'AC14AECE2E0681EE730A4D773F3B2EE6';
  static const String nsComicDecryptKey =
      'D94E86BC48615C397146E9A1CA0870E244F2C7920D7535D2F20039E9D54AD810';
  static const String nsComicDecryptIv = 'CA87D9018CC39C86FA25E7876AC079CB';

  /// host.txt 源（Constants.kt Lg/n/i/a;）。
  static const List<String> hostTxtUrls = [
    'https://m1.mmlu1.site/host.txt',
    'https://n1.mmlu1.site/host.txt',
  ];
}

/// APK 版本相关固定头。
class MmluConstants {
  MmluConstants._();

  static const String platform = 'Android';
  static const String version = '1.5.20';
  static const String appNameHeader = 'X-App-Name';
  static const String appNameValue = 'app';
  static const String responseLengthHeader = 'X-Response-Length';
  static const String authorizationHeader = 'Authorization';
  static const String authScheme = 'Bearer';
  static const String payloadHeader = 'payload';
  static const String ebodyHeader = 'ebody';
}

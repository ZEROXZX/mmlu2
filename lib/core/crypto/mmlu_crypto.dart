import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart';

/// mmlu v1.5.20 协议加密原语。
///
/// 对应 dex:
///  - EncodeUtility  Lg/n/o/c;   (code_off 5266556~5267416)
///  - G2             Lg/j/a/d/d/o/f;->G2 (mid 35324)
///  - RequestHashBean <init> (code_off 5076160)
///  - 响应解密        Lg/n/l/a/i;->invoke (mid 50041)
///
/// 复刻要点：
///  * [md5HexZp]      = Integer.toHexString 逐字节、左补零到2位、小写（EncodeUtility.f）。
///  * [md5HexBigInt]  = new BigInteger(1, md5(bytes)).toString(16)：小写、**不补零**。
///    ebody 的 AES key 必须用它（而非 md5HexZp）。
///  * [g2]            = md5HexZp(s).substring(8,24)，16 字符，用作 IV。
class MmluCrypto {
  MmluCrypto._();

  // ---- MD5 家族 -------------------------------------------------------------

  /// `Integer.toHexString(b & 0xff)` 逐字节、不足2位左补 `0`、小写。
  static String md5HexZp(String s) => _hex(_md5(utf8.encode(s)));

  /// `MD5hex`（无前导零，`BigInteger(1,digest).toString(16)`）。
  static String md5HexBigInt(List<int> data) {
    final h = _hex(_md5(data));
    final stripped = h.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? '0' : stripped;
  }

  /// `G2(s) = md5HexZp(s).substring(8, 24)` —— 16 字符。
  static String g2(String s) => md5HexZp(s).substring(8, 24);

  /// SHA-256 小写 hex（64 字符）。设备注册 `key` 用：
  /// `SHA-256("hcg" + universal_id + "hcg").hexdigest()`。
  static String sha256Hex(String s) => _hex(c.sha256.convert(utf8.encode(s)).bytes);

  static Uint8List _md5(List<int> data) =>
      Uint8List.fromList(c.md5.convert(data).bytes);

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// 十六进制字符串 → 字节。
  static Uint8List hexDecode(String hex) {
    final s = hex.trim();
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  // ---- Base64 (Android 语义) ------------------------------------------------

  /// `Base64.decode(s, DEFAULT)` (flag 0)。
  static Uint8List b64DecodeDefault(String s) =>
      Uint8List.fromList(base64.decode(s));

  /// `Base64.decode(s, NO_WRAP)` (flag 2) —— 与标准 base64 解码一致。
  static Uint8List b64DecodeNoWrap(String s) =>
      Uint8List.fromList(base64.decode(s));

  /// `Base64.encodeToString(b, NO_WRAP)` (flag 2) —— 不带换行的标准 base64。
  static String b64EncodeNoWrap(List<int> b) => base64.encode(b);

  // ---- AES/CBC/PKCS5Padding --------------------------------------------------

  static Uint8List aesCbcEncrypt(
      Uint8List key, Uint8List iv, Uint8List plain) {
    final cbc = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        true,
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );
    return cbc.process(plain);
  }

  static Uint8List aesCbcDecrypt(
      Uint8List key, Uint8List iv, Uint8List cipherText) {
    final cbc = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        false,
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );
    return cbc.process(cipherText);
  }

  // ---- 协议单元 --------------------------------------------------------------

  /// 生成 10 位 nonce：`ThreadLocalRandom.nextLong(0x3b9aca00, 0x2540be3ff)`。
  ///
  /// 区间 [1_000_000_000, 9_999_999_999) —— 上界常量 0x2540be3ff = 9_999_999_999。
  /// Dart `Random.nextInt` 上界为 2^32，故按位生成：首位 1..9，其余 9 位 0..9。
  static String newNonce([int? seed]) {
    final rnd = seed == null ? Random.secure() : Random(seed);
    final sb = StringBuffer()..write(1 + rnd.nextInt(9));
    for (var i = 0; i < 9; i++) {
      sb.write(rnd.nextInt(10));
    }
    return sb.toString();
  }

  /// 构造 ebody（对应 RequestHashBean 2 参构造，code_off 5076160）。
  ///
  /// 明文 = `{"path": path, "payload": G2(nonce)}`（Gson 字段顺序 path,payload）。
  static String buildEbody({
    required String secureKey,
    required String path,
    required String nonce,
  }) {
    final keyBytes = b64DecodeDefault(secureKey);
    final keyStr = md5HexBigInt(keyBytes); // ⚠ 不补零的小写 hex
    final key = Uint8List.fromList(utf8.encode(keyStr));
    final iv = Uint8List.fromList(utf8.encode(g2(nonce)));
    final plain = utf8.encode(jsonEncode({
      'path': path,
      'payload': g2(nonce),
    }));
    final out = aesCbcEncrypt(key, iv, Uint8List.fromList(plain));
    return b64EncodeNoWrap(out);
  }

  /// 解密响应体（对应 Lg/n/l/a/i;->invoke，mid 50041）。
  ///
  /// key = `md5HexZp(apiKey)`（补零，32 字节），iv = `G2(X-Response-Length)`。
  static String decryptResponse({
    required String apiKey,
    required String xResponseLength,
    required String bodyBase64,
  }) {
    final key = Uint8List.fromList(utf8.encode(md5HexZp(apiKey)));
    final iv = Uint8List.fromList(utf8.encode(g2(xResponseLength)));
    final plain = aesCbcDecrypt(key, iv, b64DecodeNoWrap(bodyBase64));
    return utf8.decode(plain, allowMalformed: true);
  }

  /// 解密 host.txt（对应 Lg/n/l/a/j;->invoke，mid 50044）。
  ///
  /// key = Base64.decode(hostKey)，iv = Base64.decode(hostIv)，
  /// AES-256-CBC/PKCS5 解密后取 `substring(32, len-32)`。
  static String decryptHost({
    required String hostKey,
    required String hostIv,
    required String bodyBase64,
  }) {
    final key = b64DecodeDefault(hostKey);
    final iv = b64DecodeDefault(hostIv);
    final plain = utf8.decode(aesCbcDecrypt(key, iv, b64DecodeNoWrap(bodyBase64)));
    if (plain.length <= 64) return '';
    return plain.substring(32, plain.length - 32);
  }

  // ---- 资源（图片）解密，见 docs/PROTOCOL.md §9C.7 --------------------------

  /// 动漫图：AES-128-CBC，固定密钥（hex）。
  static Uint8List decryptAnimatImage(
    Uint8List cipher, {
    required String keyHex,
    required String ivHex,
  }) =>
      aesCbcDecrypt(hexDecode(keyHex), hexDecode(ivHex), cipher);

  /// 漫画(ns)：AES-256-CBC，固定密钥（hex）。
  static Uint8List decryptNsComicImage(
    Uint8List cipher, {
    required String keyHex,
    required String ivHex,
  }) =>
      aesCbcDecrypt(hexDecode(keyHex), hexDecode(ivHex), cipher);

  /// 逐图下发：AES-256-CBC，key/iv 为 Base64 字符串。
  static Uint8List decryptPerImage(
    Uint8List cipher, {
    required String keyB64,
    required String ivB64,
  }) =>
      aesCbcDecrypt(b64DecodeDefault(keyB64), b64DecodeDefault(ivB64), cipher);
}

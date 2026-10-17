import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/data/service/hls_proxy.dart';
import 'package:mmlu_client/data/service/stream_service.dart';

/// 锁定代理的 m3u8 改写契约：去 KEY 行、分片行改写、与 parseM3u8 索引对齐。
void main() {
  group('HlsProxy.rewritePlaylist', () {
    const sample = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:6
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-KEY:METHOD=AES-128,URI="https://na.mmlu1.site/apen/K/key.php",IV=0x00112233445566778899AABBCCDDEEFF
#EXTINF:6.006000,
https://na.mmlu1.site/apen/K/ts/K-0.ts
#EXTINF:6.006000,
https://na.mmlu1.site/apen/K/ts/K-1.ts
#EXT-X-ENDLIST
''';

    test('去掉 EXT-X-KEY、保留时序指令、分片改写为本机地址', () {
      final out = HlsProxy.rewritePlaylist(
          sample, (i) => 'http://127.0.0.1:1140/seg?i=$i');

      expect(out.contains('#EXT-X-KEY'), isFalse,
          reason: '代理端解密，必须去掉密钥声明避免播放器二次解密');
      expect(out, contains('#EXTM3U'));
      expect(out, contains('#EXT-X-VERSION:6'));
      expect(out, contains('#EXTINF:6.006000,'));
      expect(out, contains('#EXT-X-ENDLIST'));

      final idxs = RegExp(r'seg\?i=(\d+)')
          .allMatches(out)
          .map((m) => m.group(1))
          .toList();
      expect(idxs, ['0', '1'], reason: '分片按出现顺序重编号');
    });

    test('无 scheme 前缀的分片行也识别，且与 parseM3u8 分片数一致', () {
      const noScheme = '''
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="https://h/key.php",IV=0x00
#EXTINF:6.0,
na.mmlu1.site/apen/K/ts/K-0.ts
#EXTINF:6.0,
na.mmlu1.site/apen/K/ts/K-1.ts
#EXTINF:6.0,
na.mmlu1.site/apen/K/ts/K-2.ts
''';
      final info = StreamService.parseM3u8(noScheme);
      final out = HlsProxy.rewritePlaylist(noScheme, (i) => 'seg$i');

      final rewritten =
          out.split('\n').where((l) => l.startsWith('seg')).toList();
      expect(rewritten, ['seg0', 'seg1', 'seg2'],
          reason: '改写索引必须与 parseM3u8 的分片顺序对齐');
      expect(info.segments.length, 3);
      expect(info.segments.first, 'https://na.mmlu1.site/apen/K/ts/K-0.ts');
    });

    test('空行/尾随换行不影响计数', () {
      const messy = '#EXTM3U\n\n#EXTINF:6.0,\n\na.ts\n\n#EXTINF:6.0,\nb.ts\n';
      final out = HlsProxy.rewritePlaylist(messy, (i) => 'x$i');
      expect(RegExp(r'x(\d+)').allMatches(out).length, 2);
    });
  });

  group('mediaPath 编码', () {
    test('base64url 往返且无 URL 特殊字符', () {
      const path = '/v3/nsanimat/media/720/JDXA55712.m3u8?a=1&b=2';
      final enc = HlsProxy.encodeMediaPath(path);
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(enc), isTrue);
      expect(HlsProxy.decodeMediaPath(enc), path);
    });
  });

  group('StreamService.partName', () {
    test('定宽 6 位，字典序 == 数字序（拼接顺序保证）', () {
      final names = [9, 0, 100, 50].map(StreamService.partName).toList();
      final sorted = [...names]..sort();
      expect(sorted, [0, 9, 50, 100].map(StreamService.partName).toList());
      expect(StreamService.partName(7), '000007.ts');
    });
  });
}

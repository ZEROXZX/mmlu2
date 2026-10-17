import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/core/constants/mmlu_keys.dart';
import 'package:mmlu_client/core/crypto/mmlu_crypto.dart';
import 'package:mmlu_client/data/models/content.dart';
import 'package:mmlu_client/data/service/stream_service.dart';

void main() {
  group('hexDecode', () {
    test('解析十六进制', () {
      expect(MmluCrypto.hexDecode('ff00AB'), equals([0xff, 0x00, 0xab]));
      expect(MmluCrypto.hexDecode(MmluKeys.nsAnimeImageDecryptKey).length, 16);
      expect(MmluCrypto.hexDecode(MmluKeys.nsComicDecryptKey).length, 32);
    });
  });

  group('图片解密（往返）', () {
    test('动漫图 AES-128 固定密钥往返', () {
      final key = MmluCrypto.hexDecode(MmluKeys.nsAnimeImageDecryptKey);
      final iv = MmluCrypto.hexDecode(MmluKeys.nsAnimeImageDecryptIv);
      final plain = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final ct = MmluCrypto.aesCbcEncrypt(key, iv, plain);
      final out = MmluCrypto.decryptAnimatImage(
        ct,
        keyHex: MmluKeys.nsAnimeImageDecryptKey,
        ivHex: MmluKeys.nsAnimeImageDecryptIv,
      );
      expect(out, equals(plain));
    });

    test('漫画 ns AES-256 固定密钥往返', () {
      final key = MmluCrypto.hexDecode(MmluKeys.nsComicDecryptKey);
      final iv = MmluCrypto.hexDecode(MmluKeys.nsComicDecryptIv);
      final plain = Uint8List.fromList(List<int>.generate(48, (i) => 255 - i));
      final ct = MmluCrypto.aesCbcEncrypt(key, iv, plain);
      final out = MmluCrypto.decryptNsComicImage(
        ct,
        keyHex: MmluKeys.nsComicDecryptKey,
        ivHex: MmluKeys.nsComicDecryptIv,
      );
      expect(out, equals(plain));
    });

    test('逐图 Base64 密钥往返', () {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => (i * 7) & 0xff));
      final iv = Uint8List.fromList(List<int>.generate(16, (i) => (i * 3) & 0xff));
      final plain = Uint8List.fromList(List<int>.generate(80, (i) => i * 2 & 0xff));
      final ct = MmluCrypto.aesCbcEncrypt(key, iv, plain);
      final out = MmluCrypto.decryptPerImage(
        ct,
        keyB64: base64.encode(key),
        ivB64: base64.encode(iv),
      );
      expect(out, equals(plain));
    });
  });

  group('m3u8 解析', () {
    test('提取 keyUri / IV / 分片', () {
      const text = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-KEY:METHOD=AES-128,URI="https://na.mmlu1.site/apen/ABC/key.php",IV=0x0123456789ABCDEF0123456789ABCDEF
#EXTINF:6.0,
https://na.mmlu1.site/apen/ABC/ts/ABC-0.ts
https://na.mmlu1.site/apen/ABC/ts/ABC-1.ts
''';
      final info = StreamService.parseM3u8(text);
      expect(info.keyUri, 'https://na.mmlu1.site/apen/ABC/key.php');
      expect(info.iv!.length, 16);
      expect(info.iv![0], 0x01);
      expect(info.segments.length, 2);
      expect(info.segments.first.endsWith('ABC-0.ts'), isTrue);
    });

    test('无协议前缀的分片补 https', () {
      const text = '#EXTM3U\nna.mmlu1.site/apen/X/ts/X-0.ts\n';
      final info = StreamService.parseM3u8(text);
      expect(info.segments.single, 'https://na.mmlu1.site/apen/X/ts/X-0.ts');
    });

    test('无 scheme 的 KEY URI 补 https（AV 动漫常见）', () {
      const text = '#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,'
          'URI="stream-encrypt1.mmlutech.xyz/apen/ABC/key.php?Expires=1&Key-Pair-Id=K"\n'
          'stream-shturl.cc/apen/ABC/ts/ABC-0.ts\n';
      final info = StreamService.parseM3u8(text);
      expect(info.keyUri,
          'https://stream-encrypt1.mmlutech.xyz/apen/ABC/key.php?Expires=1&Key-Pair-Id=K');
      expect(info.segments.single,
          'https://stream-shturl.cc/apen/ABC/ts/ABC-0.ts');
    });

    test('协议相对（//host）的 KEY URI 与分片补 https:', () {
      const text = '#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="//cdn.example.com/k.php"\n'
          '//cdn.example.com/ts/0.ts\n';
      final info = StreamService.parseM3u8(text);
      expect(info.keyUri, 'https://cdn.example.com/k.php');
      expect(info.segments.single, 'https://cdn.example.com/ts/0.ts');
    });
  });

  group('ContentItem 解析', () {
    test('动漫条目（含 media 画质）', () {
      final item = ContentItem.fromJson(ContentKind.animat, {
        'id': 733,
        'name': '测试番',
        'avkey': 'JDXA55712',
        'thumbpath': '/imgs/thumb/aa/bb.jpg',
        'media': {'720': '/v3/nsanimat/media/720/JDXA55712.m3u8', '240': '/x/240.m3u8'},
      });
      expect(item.id, 733);
      expect(item.title, '测试番');
      expect(item.avkey, 'JDXA55712');
      expect(item.thumbPath, '/imgs/thumb/aa/bb.jpg');
      expect(item.qualityKeys.first, '720');
    });

    test('漫画(ns) 封面用固定方案', () {
      final item = ContentItem.fromJson(ContentKind.comicNs, {
        'id': 5,
        'title': '漫画',
        'cover': {'cover_path': '/p/cover.jpg', 'key': 'AB', 'iv': 'CD'},
      });
      expect(item.cover!.scheme, ImageScheme.nsComic);
      expect(item.cover!.path, '/p/cover.jpg');
    });

    test('图集封面用逐图方案', () {
      final item = ContentItem.fromJson(ContentKind.photo, {
        'id': 9,
        'name': '写真',
        'cover': {'cover_path': '/p/c.jpg', 'key': 'QQ==', 'iv': 'eA=='},
      });
      expect(item.cover!.scheme, ImageScheme.perImage);
      expect(item.cover!.key, 'QQ==');
    });

    test('漫画 ns 封面若为 Base64 密钥 → 自动改用逐图方案', () {
      // 列表接口是 64 位 hex（=固定密钥）；收藏等接口可能改成 Base64。
      final b64 = base64.encode(
        Uint8List.fromList(List<int>.generate(32, (i) => i)),
      );
      final item = ContentItem.fromJson(ContentKind.comicNs, {
        'id': 7,
        'title': '收藏漫画',
        'cover': {
          'cover_path': '/p/c.jpg',
          'key': b64,
          'iv': 'CA87D9018CC39C86FA25E7876AC079CB',
        },
      });
      expect(item.cover!.scheme, ImageScheme.perImage);
      expect(item.cover!.key, b64);
    });

    test('漫画 ns 封面 hex 密钥仍走固定方案', () {
      final item = ContentItem.fromJson(ContentKind.comicNs, {
        'id': 8,
        'title': '漫画',
        'cover': {
          'cover_path': '/p/c.jpg',
          'key': MmluKeys.nsComicDecryptKey,
          'iv': MmluKeys.nsComicDecryptIv,
        },
      });
      expect(item.cover!.scheme, ImageScheme.nsComic);
    });

    test('小说条目没有封面（cover 为空）', () {
      final item = ContentItem.fromJson(ContentKind.fiction, {
        'id': 3,
        'title': '小说',
        'filepath': '/zhcn/a.txt',
      });
      expect(item.cover, isNull);
      expect(item.thumbPath, isNull);
    });
  });

  group('相似作品（samelike / photo similar）', () {
    // 实测样例：v2/combine/animat/internal/449 的 samelike[] 项。
    test('动漫 samelike 项带 source/series/ep', () {
      final item = ContentItem.fromJson(ContentKind.animat, {
        'id': 447,
        'avkey': 'JVDW-146',
        'name': '必杀痴汉人 后编',
        'series': '必杀痴汉人',
        'season': null,
        'ep': 2,
        'source': 'av',
        'coverpath': '/imgs/cover/6b/97b01e1b5e.jpg',
        'thumbpath': '/imgs/thumb/af/97b01e1b5e.jpg',
        'media': {'720': '/v1/animat/media/720/JVDW-146.m3u8'},
      });
      expect(item.id, 447);
      expect(item.series, '必杀痴汉人');
      expect(item.ep, 2);
      expect(item.source, 'av');
      expect(item.media['720'], contains('JVDW-146'));
    });

    // 实测样例：v3/photo/similar?id=64483 的 data[] 项（cover 为 Map）。
    test('图集 similar 项 cover 为 Map 且逐图方案', () {
      final item = ContentItem.fromJson(ContentKind.photo, {
        'id': 64556,
        'name': '[兔玩映畫] 样例',
        'tag': ['少女', '巨乳'],
        'cover': {
          'cover_path': 'd31d70dea5e0b425f544b9faa580da7d/cover.jpg',
          'key': 'MoZzQQ3I/pKrrTHBTGbbJikY6gRFTnV1zpfOu5irxNw=',
          'iv': '2DyTxRsI4+R3dQ/LgXXojg==',
        },
        'view_count': 828,
      });
      expect(item.id, 64556);
      expect(item.cover!.scheme, ImageScheme.perImage);
      expect(item.cover!.path, contains('cover.jpg'));
      expect(item.cover!.key, isNotEmpty);
      expect(item.tags, contains('少女'));
    });
  });

  group('FictionChapter 解析', () {
    test('filepath / filepath_tw', () {
      final c = FictionChapter.fromJson({
        'title': '第一章',
        'filepath': '/zhcn/A/1.txt',
        'filepath_tw': '/zhtw/A/1.txt',
      });
      expect(c.title, '第一章');
      expect(c.path, '/zhcn/A/1.txt');
      expect(c.pathTw, '/zhtw/A/1.txt');
    });
  });

  group('source 路由', () {
    test('动漫条目带 source=av', () {
      final item = ContentItem.fromJson(ContentKind.animat, {
        'id': 11354,
        'name': 'av 番',
        'avkey': 'animate01714',
        'source': 'av',
        'media': {'720': '/v1/animat/media/720/animate01714.m3u8'},
      });
      expect(item.source, 'av');
      expect(item.media['720'], '/v1/animat/media/720/animate01714.m3u8');
    });
  });

  group('Chapter 解析', () {
    test('漫画 av：chapter_id 优先于 id', () {
      final c = Chapter.fromJson(ContentKind.comicAv, {
        'id': 129868,
        'chapter_id': 378976,
        'chapter': 1,
        'name': '第1话',
      });
      expect(c.chapterId, 378976);
      expect(c.number, 1);
    });

    test('漫画 ns：无 chapter_id 时回退 id', () {
      final c = Chapter.fromJson(ContentKind.comicNs, {
        'id': 368760,
        'chapter': 16,
        'name': '第 16 话',
      });
      expect(c.chapterId, 368760);
      expect(c.number, 16);
    });
  });
}


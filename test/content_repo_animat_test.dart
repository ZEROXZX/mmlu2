import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/core/domain/domain_store.dart';
import 'package:mmlu_client/core/network/api_client.dart';
import 'package:mmlu_client/core/network/api_exception.dart';
import 'package:mmlu_client/data/api/api_service.dart';
import 'package:mmlu_client/data/models/content.dart';
import 'package:mmlu_client/data/repo/content_repo.dart';
import 'package:mmlu_client/core/auth/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录调用并可控返回/抛错的假接口层。
class _FakeApi extends ApiService {
  _FakeApi(super.client);

  int nsCalls = 0;
  int avCalls = 0;
  Object? nsResult;
  Object? avResult;
  Object? photoResult;

  final addCalls = <String>[];
  Object? addResult;
  final favBySource = <String, List<Map<String, dynamic>>>{};

  @override
  Future<Object?> photoRead({
    required int id,
    int counts = 0,
    int pages = 0,
  }) async =>
      photoResult;

  @override
  Future<Object?> photoSimilar(int id) async => {'data': const []};

  @override
  Future<Object?> favorites(String kind,
          {int counts = 20, int pages = 1, String? source}) async =>
      {'data': favBySource['$kind:${source ?? ''}'] ?? const []};

  @override
  Future<Object?> addFavorite(String kind, int id, {String? source}) async {
    addCalls.add('add:$kind:$id:${source ?? ''}');
    return addResult;
  }

  @override
  Future<Object?> removeFavorite(String kind, List<int> ids,
      {String? source}) async {
    addCalls.add('rm:$kind:${ids.join(",")}:${source ?? ''}');
    return addResult;
  }

  @override
  Future<Object?> nsAnimatDetail(int id) async {
    nsCalls++;
    final r = nsResult;
    if (r is Exception) throw r;
    return r;
  }

  @override
  Future<Object?> animatDetail(int id) async {
    avCalls++;
    final r = avResult;
    if (r is Exception) throw r;
    return r;
  }
}

Map<String, dynamic> _detail(int id, String name, String source) => {
      'summary': [
        {'id': id, 'name': name, 'source': source, 'media': {'720': '/m/$id.m3u8'}},
      ],
      'directory': const [],
      'samelike': const [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeApi api;
  late ContentRepo repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = ApiClient(
      tokenStore: TokenStore(prefs),
      domainStore: DomainStore(prefs),
    );
    api = _FakeApi(client);
    repo = ContentRepo(api);
  });

  group('动漫详情按 source 路由（AV/NS 是两套 id 空间）', () {
    test("source='av' → 只走 v2/combine/animat", () async {
      api.avResult = _detail(14767, '鬼父', 'av');
      api.nsResult = _detail(14767, '【MMD】别的东西', 'ns');

      final d = await repo.detail(ContentKind.animat, 14767, source: 'av');
      expect(d.item.title, '鬼父');
      expect(api.avCalls, 1);
      expect(api.nsCalls, 0);
    });

    test("source='ns' → 只走 v3/nsanimat", () async {
      api.nsResult = _detail(5, 'NS作品', 'ns');
      api.avResult = _detail(5, 'AV作品', 'av');

      final d = await repo.detail(ContentKind.animat, 5, source: 'ns');
      expect(d.item.title, 'NS作品');
      expect(api.nsCalls, 1);
      expect(api.avCalls, 0);
    });

    test('source 缺省时默认走 ns', () async {
      api.nsResult = _detail(5, 'NS作品', 'ns');
      await repo.detail(ContentKind.animat, 5);
      expect(api.nsCalls, 1);
    });

    test("AV 详情 410 → 回退 nsanimat", () async {
      api.avResult = ApiException(410, '资源无法存取');
      api.nsResult = _detail(5, 'NS回退', 'ns');

      final d = await repo.detail(ContentKind.animat, 5, source: 'av');
      expect(d.item.title, 'NS回退');
      expect(api.avCalls, 1);
      expect(api.nsCalls, 1);
    });

    test("NS 详情 410 → 回退 combine/animat", () async {
      api.nsResult = ApiException(410, '资源无法存取');
      api.avResult = _detail(9, 'AV回退', 'av');

      final d = await repo.detail(ContentKind.animat, 9, source: 'ns');
      expect(d.item.title, 'AV回退');
      expect(api.nsCalls, 1);
      expect(api.avCalls, 1);
    });

    test('非 410 错误直接抛出，不回退', () async {
      api.nsResult = ApiException(500, 'boom');
      api.avResult = _detail(9, '不该到这里', 'av');

      expect(
        () => repo.detail(ContentKind.animat, 9, source: 'ns'),
        throwsA(isA<ApiException>()),
      );
      expect(api.avCalls, 0);
    });
  });

  group('图集详情（photoRead 只返回页表）', () {
    test('用首张图补出预览封面，并保留传入 id', () async {
      api.photoResult = {
        'data': [
          {'image_path': 'a/0001.jpg', 'key': 'k1==', 'iv': 'iv1=='},
          {'image_path': 'a/0002.jpg', 'key': 'k2==', 'iv': 'iv2=='},
        ],
      };

      final d = await repo.detail(ContentKind.photo, 64483);

      expect(d.item.id, 64483, reason: 'id 需补回，否则阅读页会请求 id=0');
      expect(d.item.cover, isNotNull, reason: '预览封面来自首张图');
      expect(d.item.cover!.path, 'a/0001.jpg');
      expect(d.item.cover!.scheme, ImageScheme.perImage);
      expect(d.item.cover!.key, 'k1==');
      expect(d.item.cover!.iv, 'iv1==');
    });
  });

  group('收藏（动漫按 source 路由 / AV+NS 合并 / 错误抛出）', () {
    test('NS 作品收藏打到 ns 源，AV 作品打到 av 源', () async {
      api.addResult = {'success': true};
      await repo.addFavorite(ContentKind.animat, 7, source: 'ns');
      await repo.addFavorite(ContentKind.animat, 8, source: 'av');
      expect(api.addCalls, ['add:animat:7:ns', 'add:animat:8:av']);
    });

    test('取消收藏同样按 source 路由', () async {
      api.addResult = {'success': true};
      await repo.removeFavorite(ContentKind.animat, [7], source: 'ns');
      expect(api.addCalls.single, 'rm:animat:7:ns');
    });

    test('动漫收藏列表合并 AV 与 NS 并去重', () async {
      api.favBySource['animat:av'] = [
        {'id': 1, 'name': 'AV作品', 'source': 'av'},
        {'id': 2, 'name': 'AV作品2', 'source': 'av'},
      ];
      api.favBySource['animat:ns'] = [
        {'id': 2, 'name': 'AV作品2', 'source': 'av'},
        {'id': 9, 'name': 'NS作品', 'source': 'ns'},
      ];

      final list = await repo.favorites(ContentKind.animat);

      expect(list.map((e) => '${e.id}:${e.source}').toSet(),
          {'1:av', '2:av', '9:ns'});
    });

    test('收藏返回 error 信封 → 抛 ApiException（不再静默失败）', () async {
      api.addResult = {
        'error': {'msg': '请先登录', 'code': 401}
      };
      expect(
        () => repo.addFavorite(ContentKind.animat, 7, source: 'ns'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}

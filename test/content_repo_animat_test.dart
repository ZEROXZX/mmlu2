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
}

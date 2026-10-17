import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/core/auth/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TokenStore.universalId', () {
    test('首次生成 v4 UUID 并持久化；再次读取保持不变', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = TokenStore(prefs);

      final a = store.universalId;
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(a),
        isTrue,
      );
      // 同一实例与新实例两次读取一致（跨会话稳定）。
      expect(store.universalId, a);
      final again = TokenStore(await SharedPreferences.getInstance());
      expect(again.universalId, a);
    });
  });

  group('TokenStore 登录态标记', () {
    test('游客 token 不算已登录；markLoggedIn 后为 true，clear 复位', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TokenStore(await SharedPreferences.getInstance());

      await store.save('guest-token');
      expect(store.token, 'guest-token');
      expect(store.isLoggedIn, isFalse);

      await store.markLoggedIn(true);
      expect(store.isLoggedIn, isTrue);

      await store.clear();
      expect(store.token, isNull);
      expect(store.isLoggedIn, isFalse);
    });
  });
}

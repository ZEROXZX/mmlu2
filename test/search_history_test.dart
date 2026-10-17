import 'package:flutter_test/flutter_test.dart';
import 'package:mmlu_client/data/service/search_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史：无上限、去重置顶、逐条删除 / 清空。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无数量上限：连续 add 不受 10/20 之类限制', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SearchHistoryStore(await SharedPreferences.getInstance());
    for (var i = 0; i < 60; i++) {
      await store.add('kw$i');
    }
    expect(store.load().length, 60);
    expect(store.load().first, 'kw59', reason: '最近在前');
  });

  test('重复关键词去重并置顶', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SearchHistoryStore(await SharedPreferences.getInstance());
    await store.add('a');
    await store.add('b');
    await store.add('a');
    expect(store.load(), ['a', 'b']);
  });

  test('逐条删除与清空', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SearchHistoryStore(await SharedPreferences.getInstance());
    await store.add('a');
    await store.add('b');
    await store.remove('a');
    expect(store.load(), ['b']);
    await store.clear();
    expect(store.load(), isEmpty);
  });

  test('空白关键词忽略', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SearchHistoryStore(await SharedPreferences.getInstance());
    await store.add('   ');
    expect(store.load(), isEmpty);
  });
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史（本地 SharedPreferences）。
///
/// **无数量上限**；最近搜索在前、自动去重；支持逐条删除与清空。
class SearchHistoryStore {
  SearchHistoryStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'search_history';

  List<String> load() {
    final s = _prefs.getString(_key);
    if (s == null || s.isEmpty) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => '$e')
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<String> list) =>
      _prefs.setString(_key, jsonEncode(list));

  /// 记录一条关键词：去重后置顶，**不设上限**。
  Future<void> add(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    final list = load()..removeWhere((e) => e == kw);
    list.insert(0, kw);
    await _save(list);
  }

  /// 删除单条。
  Future<void> remove(String keyword) async {
    final list = load()..removeWhere((e) => e == keyword);
    await _save(list);
  }

  /// 清空全部。
  Future<void> clear() => _save(const []);
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一条下载记录（R2.1 本地保存）。
class DownloadRecord {
  DownloadRecord({
    required this.id,
    required this.title,
    required this.kind,
    required this.filePath,
    this.quality,
    this.status = 'done',
    this.encryptedUrl,
    this.keyUrl,
    this.decryptedUrl,
    this.totalBytes = 0,
    this.coverPath,
    required this.createdAt,
  });

  /// 唯一 ID（一般 = `kind_id[_quality]`）。
  final String id;
  final String title;
  final String kind;

  /// 画质档位（动漫）。
  final String? quality;

  /// pending / downloading / done / failed。
  String status;

  /// 本地产物路径（.mp4 / .zip / .txt）。
  final String filePath;

  /// R1.4 三条链接。
  final String? encryptedUrl;
  final String? keyUrl;
  final String? decryptedUrl;

  final int totalBytes;
  final String? coverPath;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'quality': quality,
        'status': status,
        'filePath': filePath,
        'encryptedUrl': encryptedUrl,
        'keyUrl': keyUrl,
        'decryptedUrl': decryptedUrl,
        'totalBytes': totalBytes,
        'coverPath': coverPath,
        'createdAt': createdAt,
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> j) => DownloadRecord(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        quality: j['quality']?.toString(),
        status: (j['status'] ?? 'done').toString(),
        filePath: (j['filePath'] ?? '').toString(),
        encryptedUrl: j['encryptedUrl']?.toString(),
        keyUrl: j['keyUrl']?.toString(),
        decryptedUrl: j['decryptedUrl']?.toString(),
        totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
        coverPath: j['coverPath']?.toString(),
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// 下载历史存储（本地 SharedPreferences；R2.2 显示 / R2.3 选择性删除）。
class DownloadStore {
  DownloadStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'download_history';

  List<DownloadRecord> load() {
    final s = _prefs.getString(_key);
    if (s == null || s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .whereType<Map>()
          .map((e) => DownloadRecord.fromJson(e.cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<DownloadRecord> list) =>
      _prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));

  Future<void> upsert(DownloadRecord rec) async {
    final list = load()..removeWhere((r) => r.id == rec.id);
    list.insert(0, rec);
    await _save(list);
  }

  Future<void> removeMany(Iterable<String> ids) async {
    final set = ids.toSet();
    final list = load()..removeWhere((r) => set.contains(r.id));
    await _save(list);
  }

  Future<void> clear() => _save([]);
}

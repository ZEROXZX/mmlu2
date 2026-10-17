

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

class BannerItem {
  BannerItem({required this.name, required this.img, this.destn, this.src, this.method});

  final String name;
  final String img;
  final String? destn;
  final String? src;
  final int? method;

  factory BannerItem.fromJson(Map<String, dynamic> j) => BannerItem(
        name: (j['name'] ?? '').toString(),
        img: (j['img'] ?? '').toString(),
        destn: j['destn']?.toString(),
        src: j['src']?.toString(),
        method: _asInt(j['method']),
      );
}
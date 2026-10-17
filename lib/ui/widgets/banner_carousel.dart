import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_container.dart';
import '../../data/models/banner.dart';
import '../widgets/async_view.dart';

/// 首页 Banner 轮播。
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late Future<List<BannerItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppContainer>().contentRepo.getBanners();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: AsyncView<List<BannerItem>>(
        future: _future,
        onRetry: () => setState(() => _future = context.read<AppContainer>().contentRepo.getBanners()),
        builder: (context, items) => PageView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final b = items[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(b.img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200)),
              ),
            );
          },
        ),
      ),
    );
  }
}

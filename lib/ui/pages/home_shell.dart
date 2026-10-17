import 'package:flutter/material.dart';

import 'account_page.dart';
import 'category_tab.dart';
import 'downloads_page.dart';
import 'favorites_tab.dart';
import 'home_tab.dart';
import 'search_tab.dart';

/// 主框架：底部导航 首页 / 分类 / 搜索 / 收藏 / 下载；右上角进入账号页。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['首页', '分类', '搜索', '收藏', '下载'];

  @override
  Widget build(BuildContext context) {
    const tabs = [
      HomeTab(),
      CategoryTab(),
      SearchTab(),
      FavoritesTab(),
      DownloadsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: '账号',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountPage()),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: '分类'),
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.favorite_border), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.download_outlined), label: '下载'),
        ],
      ),
    );
  }
}

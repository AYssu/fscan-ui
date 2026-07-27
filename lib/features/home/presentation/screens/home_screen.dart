import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 主页面 - 包含底部导航栏
class HomeScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const HomeScreen({super.key, required this.navigationShell});

  /// 导航到指定分支
  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            selectedIcon: Icon(Icons.qr_code_scanner_outlined),
            label: '扫描',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows),
            selectedIcon: Icon(Icons.compare_arrows_outlined),
            label: '对比',
          ),
          NavigationDestination(
            icon: Icon(Icons.filter_list),
            selectedIcon: Icon(Icons.filter_list_outlined),
            label: '过滤',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune),
            selectedIcon: Icon(Icons.tune_outlined),
            label: '基础',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            selectedIcon: Icon(Icons.settings_outlined),
            label: '配置',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fscan/core/theme/theme_provider.dart';

/// 配置页面 - MD3 风格
class ConfigScreen extends StatelessWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('配置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 用户信息
            _buildUserCard(context),
            const SizedBox(height: 16),

            // 主题设置
            _buildThemeCard(context, themeProvider),
            const SizedBox(height: 16),

            // 存储设置
            _buildStorageCard(context),
            const SizedBox(height: 16),

            // 关于
            _buildAboutCard(context),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 用户信息卡片
  Widget _buildUserCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                'F',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FastScan', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('v1.0.0', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: () {},
              child: const Text('已激活'),
            ),
          ],
        ),
      ),
    );
  }

  /// 主题设置卡片
  Widget _buildThemeCard(BuildContext context, ThemeProvider themeProvider) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.palette, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('主题设置', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('深色模式'),
            subtitle: Text(themeProvider.isDarkMode ? '已开启' : '已关闭'),
            value: themeProvider.isDarkMode,
            onChanged: (v) => themeProvider.toggleTheme(),
            secondary: Icon(
              themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('主题颜色'),
            subtitle: const Text('蓝色'),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  /// 存储设置卡片
  Widget _buildStorageCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.storage, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('存储设置', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          ListTile(
            title: const Text('配置文件'),
            subtitle: const Text('/sdcard/fscan/config/'),
            onTap: () {},
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('扫描数据'),
            subtitle: const Text('/sdcard/fscan/data/'),
            onTap: () {},
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('缓存大小'),
            trailing: Text('12.5 MB', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  /// 关于卡片
  Widget _buildAboutCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('关于', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          ListTile(
            title: const Text('版本'),
            trailing: const Text('v1.0.0'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('构建'),
            trailing: const Text('2026.07.26'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('Flutter'),
            trailing: const Text('3.12.2'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('检查更新'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

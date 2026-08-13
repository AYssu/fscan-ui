import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fscan/core/theme/theme_provider.dart';
import 'package:fscan/core/theme/background_provider.dart';
import 'package:fscan/core/config/app_config.dart';
import 'package:fscan/core/network/ws_service.dart';
import 'package:fscan/core/utils/logger.dart';
import 'package:fscan/core/utils/cache_utils.dart';
import 'package:fscan/core/services/kami_service.dart';

/// 配置页面 - MD3 风格
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  /// 预设主题颜色
  static const List<Color> presetColors = [
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.deepPurple,
    Colors.teal,
    Colors.green,
    Colors.cyan,
    Colors.pink,
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.brown,
  ];

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  String _appVersion = '';
  String _buildNumber = '';
  int _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final size = await CacheUtils.getCacheSize();
    if (mounted) {
      setState(() {
        _cacheSize = size;
      });
    }
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空缓存'),
        content: const Text('确定要清空所有缓存吗？\n\n将清除：\n• 模块配置\n• 用户登录信息\n• 日志文件\n• 头像缓存\n\n主题设置将保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              await CacheUtils.clearAllCache();
              _loadCacheSize();
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('缓存已清空')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('配置'),
        actions: [
          _buildUserAvatar(context),
        ],
      ),
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

            // 背景设置
            _buildBackgroundCard(context),
            const SizedBox(height: 16),

            // 日志
            _buildLogsCard(context),
            const SizedBox(height: 16),

            // 关于
            _buildAboutCard(context),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 用户头像按钮（卡密授权）
  Widget _buildUserAvatar(BuildContext context) {
    return Consumer<KamiService>(
      builder: (context, kamiService, child) {
        return GestureDetector(
          onTap: () => _showKamiDialog(context, kamiService),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: kamiService.isAuthorized
                ? _buildAuthorizedAvatar(context, kamiService)
                : _buildDefaultAvatar(context),
          ),
        );
      },
    );
  }

  /// 已授权头像
  Widget _buildAuthorizedAvatar(BuildContext context, KamiService kamiService) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // 显示卡密首字符
    final key = kamiService.kamiKey ?? '';
    final firstChar = key.isNotEmpty ? key[0].toUpperCase() : '?';

    return CircleAvatar(
      radius: 16,
      backgroundColor: themeProvider.seedColor,
      child: Text(
        firstChar,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 默认头像（未授权）
  Widget _buildDefaultAvatar(BuildContext context) {
    return const CircleAvatar(
      radius: 16,
      backgroundColor: Colors.grey,
      child: Icon(
        Icons.vpn_key,
        color: Colors.white,
        size: 18,
      ),
    );
  }

  /// 卡密授权弹窗
  void _showKamiDialog(BuildContext context, KamiService kamiService) {
    if (kamiService.isAuthorized) {
      // 已授权，显示卡密信息
      _showKamiInfoDialog(context, kamiService);
      return;
    }

    final kamiKeyController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('卡密授权'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: kamiKeyController,
                    decoration: const InputDecoration(
                      labelText: '卡密密钥',
                      hintText: '请输入卡密密钥',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key),
                    ),
                  ),
                  if (kamiService.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      kamiService.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (kamiKeyController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请输入卡密密钥')),
                            );
                            return;
                          }

                          setDialogState(() => isLoading = true);

                          // 查询卡密状态
                          final wsService = context.read<WsService>();
                          if (!wsService.isConnected) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请先连接服务器')),
                            );
                            setDialogState(() => isLoading = false);
                            return;
                          }

                          final response = await wsService.getKamiInfo(
                            kamiKeyController.text.trim(),
                          );

                          if (response != null && response['success'] == true) {
                            // 保存卡密信息
                            final kamiInfo = KamiInfo.fromJson(response);
                            await kamiService.saveKamiInfo(
                              kamiKeyController.text.trim(),
                              kamiInfo,
                            );

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('授权成功'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(response?['message'] ?? '卡密无效或已过期'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }

                          setDialogState(() => isLoading = false);
                        },
                  child: const Text('授权'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 卡密信息弹窗
  void _showKamiInfoDialog(BuildContext context, KamiService kamiService) {
    final kamiInfo = kamiService.kamiInfo;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('卡密信息'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 卡密图标
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: const Icon(
                        Icons.vpn_key,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kamiService.kamiKey ?? '',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (kamiInfo != null) ...[
                _buildInfoRow('卡密类型', kamiInfo.cardType),
                _buildInfoRow('到期时间', kamiInfo.formattedEndTime),
                _buildInfoRow('可用次数', '${kamiInfo.available}'),
                _buildInfoRow('绑定数量', '${kamiInfo.bindNumber}'),
                _buildInfoRow('未绑数量', '${kamiInfo.unbindNumber}'),
              ] else ...[
                const Center(
                  child: Text('暂无卡密详情', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                await kamiService.clearKamiInfo();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已取消授权')),
                );
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('取消授权'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value),
        ],
      ),
    );
  }

  /// 用户信息卡片
  Widget _buildUserCard(BuildContext context) {
    return Consumer<WsService>(
      builder: (context, wsService, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/icon.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FastScan', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('v$_appVersion', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                _buildConnectionStatus(context, wsService),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 连接状态按钮
  Widget _buildConnectionStatus(BuildContext context, WsService wsService) {
    Color buttonColor;
    String buttonText;
    IconData icon;

    switch (wsService.status) {
      case WsStatus.connected:
        buttonColor = Colors.green;
        buttonText = '已连接';
        icon = Icons.check_circle;
        break;
      case WsStatus.connecting:
      case WsStatus.reconnecting:
        buttonColor = Colors.orange;
        buttonText = '连接中';
        icon = Icons.sync;
        break;
      case WsStatus.disconnected:
        buttonColor = Colors.grey;
        buttonText = '待连接';
        icon = Icons.link_off;
        break;
    }

    return FilledButton.tonal(
      onPressed: () => _showConnectionDialog(context, wsService),
      style: FilledButton.styleFrom(
        backgroundColor: buttonColor.withValues(alpha: 0.2),
        foregroundColor: buttonColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(buttonText),
        ],
      ),
    );
  }

  /// 连接弹窗
  void _showConnectionDialog(BuildContext context, WsService wsService) {
    final urlController = TextEditingController(
      text: wsService.url ?? 'ws://localhost:8080/ws',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isMounted = true;
        void Function()? removeListener;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 监听 wsService 状态变化
            void onStatusChanged() {
              if (isMounted) {
                setDialogState(() {});
              }
            }

            // 只添加一次监听器
            removeListener ??= () {
              wsService.removeListener(onStatusChanged);
            };
            wsService.addListener(onStatusChanged);

            return AlertDialog(
              title: const Text('WebSocket 连接'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'ws://localhost:8080/ws',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (wsService.status == WsStatus.connecting ||
                      wsService.status == WsStatus.reconnecting) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(
                      wsService.status == WsStatus.connecting ? '正在连接...' : '正在重连...',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  if (wsService.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      wsService.errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    isMounted = false;
                    removeListener?.call();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('取消'),
                ),
                if (wsService.status == WsStatus.connected)
                  FilledButton(
                    onPressed: () {
                      isMounted = false;
                      wsService.disconnect();
                      removeListener?.call();
                      Navigator.pop(dialogContext);
                    },
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('断开'),
                  )
                else
                  FilledButton(
                    onPressed: wsService.status == WsStatus.connecting ||
                            wsService.status == WsStatus.reconnecting
                        ? null
                        : () async {
                            await wsService.connect(urlController.text);
                            if (wsService.isConnected && isMounted) {
                              isMounted = false;
                              removeListener?.call();
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('连接成功'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          },
                    child: const Text('连接'),
                  ),
              ],
            );
          },
        );
      },
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
            subtitle: Text(_getColorName(themeProvider.seedColor)),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: themeProvider.seedColor,
                shape: BoxShape.circle,
              ),
            ),
            onTap: () => _showColorPicker(context, themeProvider),
          ),
        ],
      ),
    );
  }

  /// 显示颜色选择器弹窗
  void _showColorPicker(BuildContext context, ThemeProvider themeProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('选择主题颜色'),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: ConfigScreen.presetColors.map((color) {
              final isSelected = themeProvider.seedColor.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () {
                  themeProvider.setSeedColor(color);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  /// 获取颜色名称
  String _getColorName(Color color) {
    final colorMap = {
      Colors.blue.toARGB32(): '蓝色',
      Colors.indigo.toARGB32(): '靛蓝',
      Colors.purple.toARGB32(): '紫色',
      Colors.deepPurple.toARGB32(): '深紫',
      Colors.teal.toARGB32(): '青色',
      Colors.green.toARGB32(): '绿色',
      Colors.cyan.toARGB32(): '天蓝',
      Colors.pink.toARGB32(): '粉色',
      Colors.red.toARGB32(): '红色',
      Colors.orange.toARGB32(): '橙色',
      Colors.amber.toARGB32(): '琥珀',
      Colors.brown.toARGB32(): '棕色',
    };
    return colorMap[color.toARGB32()] ?? '自定义';
  }

  /// 存储设置卡片
  Widget _buildStorageCard(BuildContext context) {
    return Consumer<AppConfig>(
      builder: (context, appConfig, child) {
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
                subtitle: Text(
                  appConfig.configPath,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: () => _editPath(context, appConfig, '配置文件路径', appConfig.configPath, (path) => appConfig.setConfigPath(path)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: const Text('扫描数据'),
                subtitle: Text(
                  appConfig.dataPath,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: () => _editPath(context, appConfig, '扫描数据路径', appConfig.dataPath, (path) => appConfig.setDataPath(path)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: const Text('缓存大小'),
                trailing: Text(CacheUtils.formatSize(_cacheSize), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                onTap: _showClearCacheDialog,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 编辑路径弹窗
  void _editPath(BuildContext context, AppConfig appConfig, String title, String currentValue, Future<void> Function(String) onSave) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final path = controller.text.trim();
              if (path.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('路径不能为空')),
                );
                return;
              }
              await onSave(path);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 背景设置卡片
  Widget _buildBackgroundCard(BuildContext context) {
    return Consumer<BackgroundProvider>(
      builder: (context, bgProvider, child) {
        return Card(
          child: ExpansionTile(
            leading: Icon(Icons.wallpaper, color: Theme.of(context).colorScheme.primary),
            title: Text('背景设置', style: Theme.of(context).textTheme.titleMedium),
            subtitle: bgProvider.hasBackground
                ? Text('已设置 · 背景${(bgProvider.opacity * 100).round()}% · 卡片${(bgProvider.cardOpacity * 100).round()}%',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))
                : Text('未设置', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            children: [
              // 背景预览 / 点击选择
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => _pickBackgroundImage(context, bgProvider),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: bgProvider.hasBackground
                        ? Stack(
                            children: [
                              Opacity(
                                opacity: bgProvider.opacity,
                                child: Image.file(
                                  File(bgProvider.imagePath!),
                                  height: 120,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                                  ),
                                  onPressed: () => bgProvider.clear(),
                                ),
                              ),
                            ],
                          )
                        : Container(
                            height: 120,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate, size: 36, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                const SizedBox(height: 8),
                                Text('点击选择背景图片', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 背景透明度调节
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.opacity, size: 20),
                    const SizedBox(width: 8),
                    const Text('背景透明度'),
                    const Spacer(),
                    Text(
                      '${(bgProvider.opacity * 100).round()}%',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
              Slider(
                value: bgProvider.opacity,
                min: 0.05,
                max: 1.0,
                divisions: 19,
                onChanged: (value) => bgProvider.setOpacity(value),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              // 卡片透明度调节
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.style, size: 20),
                    const SizedBox(width: 8),
                    const Text('卡片透明度'),
                    const Spacer(),
                    Text(
                      '${(bgProvider.cardOpacity * 100).round()}%',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
              Slider(
                value: bgProvider.cardOpacity,
                min: 0.3,
                max: 1.0,
                divisions: 14,
                onChanged: (value) => bgProvider.setCardOpacity(value),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickBackgroundImage(BuildContext context, BackgroundProvider bgProvider) async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      await bgProvider.setImage(result.files.single.path);
    }
  }

  /// 日志卡片
  Widget _buildLogsCard(BuildContext context) {
    return Consumer<Logger>(
      builder: (context, logger, child) {
        return Card(
          child: ListTile(
            leading: Icon(Icons.bug_report, color: Theme.of(context).colorScheme.primary),
            title: const Text('日志'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${logger.logs.length} 条',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _showLogsPage(context, logger),
          ),
        );
      },
    );
  }

  void _showLogsPage(BuildContext context, Logger logger) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _LogsPage(logger: logger),
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
            trailing: Text('v$_appVersion'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('构建'),
            trailing: Text(_buildNumber),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const ListTile(
            title: Text('Flutter'),
            trailing: Text('3.12.2'),
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

/// 日志页面
class _LogsPage extends StatelessWidget {
  final Logger logger;

  const _LogsPage({required this.logger});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              logger.clearLogs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已清空')),
              );
            },
          ),
        ],
      ),
      body: Consumer<Logger>(
        builder: (context, logger, child) {
          if (logger.logs.isEmpty) {
            return const Center(child: Text('暂无日志'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: logger.logs.length,
            itemBuilder: (context, index) {
              final log = logger.logs[logger.logs.length - 1 - index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(
                    _getLogIcon(log.level),
                    color: _getLogColor(context, log.level),
                  ),
                  title: Text(
                    log.message,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Tag: ${log.tag}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Time: ${log.timestamp.toString().substring(0, 19)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (log.error != null)
                        Text(
                          'Error: ${log.error}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.red,
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _getLogIcon(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Icons.bug_report;
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.warning:
        return Icons.warning_amber;
      case LogLevel.error:
        return Icons.error_outline;
      case LogLevel.fatal:
        return Icons.dangerous;
    }
  }

  Color _getLogColor(BuildContext context, LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Theme.of(context).colorScheme.primary;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.fatal:
        return Colors.purple;
    }
  }
}

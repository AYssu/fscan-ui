import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:fscan/core/config/app_config.dart';
import 'package:fscan/core/services/module_service.dart';
import 'package:fscan/core/network/ws_service.dart';
import 'package:fscan/core/utils/logger.dart';
import 'package:fscan/shared/widgets/terminal_panel.dart';

/// 基址搜索页面 - MD3 风格
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<String> searchAddresses = [];
  int scanLevel = 6;
  String scanRange = '0x7D0';
  bool handleB4000000 = false; // 处理 0xb4000000
  bool handlePageFault = false; // 缺页处理
  bool is32Bit = false;
  bool byteAlignment = false;
  bool pageAlignment = false;
  int scanCores = 8;
  bool moduleExtension = false;
  bool negativeOffset = false;
  bool isBrutalMode = false; // true=暴力格式, false=通用格式
  bool readProtected = false; // 读取受限内存
  String outputPath = '/storage/emulated/0/fscan/a1.out';
  String? _currentTaskId;
  bool _showTerminal = false;

  // 内存范围 - 从AppConfig获取（持久化）
  Map<String, bool> get memoryRanges => context.read<AppConfig>().memoryRanges;

  @override
  void initState() {
    super.initState();
    // 延迟到build完成后加载，避免setState错误
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initModulesIfNeeded();
      _generateOutputPath();  // 初始化时生成输出路径
    });
  }

  /// 如果有选中的包名，自动加载模块
  Future<void> _initModulesIfNeeded() async {
    final appConfig = context.read<AppConfig>();
    final wsService = context.read<WsService>();

    // 如果有选中的包名但模块未加载，则自动加载
    if (appConfig.selectedPackageName != null && !appConfig.modulesLoaded) {
      logger.info('ScanScreen', '自动加载模块: ${appConfig.selectedPackageName}');
      await appConfig.fetchAndLoadModules(wsService, appConfig.selectedPackageName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基址搜索'),
      ),
      body: Column(
        children: [
          // 主要内容区域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 目标地址
                  _buildAddressCard(),
                  const SizedBox(height: 16),

                  // 核心配置
                  _buildCoreConfigCard(),
                  const SizedBox(height: 16),

                  // 模块选择
                  _buildModuleCard(),
                  const SizedBox(height: 16),

                  // 文件选择
                  _buildFileCard(),
                  const SizedBox(height: 16),

                  // 高级选项
                  _buildAdvancedCard(),
                  const SizedBox(height: 24),

                  // 操作按钮
                  _buildActionButtons(),

                  // 终端面板（嵌入式）
                  if (_showTerminal && _currentTaskId != null) ...[
                    const SizedBox(height: 16),
                    _buildTerminalCard(),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 终端面板卡片
  Widget _buildTerminalCard() {
    return Card(
      child: Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('终端输出', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    setState(() {
                      _showTerminal = false;
                      _currentTaskId = null;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // 终端内容
          SizedBox(
            height: 250,
            child: TerminalPanel(
              key: ValueKey(_currentTaskId),
              taskId: _currentTaskId,
            ),
          ),
        ],
      ),
    );
  }

  /// 目标地址卡片
  Widget _buildAddressCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('目标地址', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),

            // 地址显示
            InkWell(
              onTap: editAddress,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        searchAddresses.isEmpty
                            ? '点击输入地址'
                            : searchAddresses.length == 1
                                ? searchAddresses.first
                                : '已输入 ${searchAddresses.length} 个地址',
                        style: TextStyle(
                          color: searchAddresses.isEmpty
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                    ),
                    Icon(Icons.edit, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 核心配置卡片
  Widget _buildCoreConfigCard() {
    return Card(
      child: Column(
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('核心配置', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),

          // 配置列表
          ListTile(
            title: const Text('扫描层级'),
            trailing: Text('$scanLevel 层', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editLevel,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('扫描范围'),
            trailing: Text(
              _formatRangeDisplay(scanRange),
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            onTap: editRange,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('输出路径'),
            subtitle: Text(
              outputPath.split('/').last,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: _generateOutputPath,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('自动生成'),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                const Text('进程位数'),
                const Spacer(),
                SizedBox(
                  width: 180,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('32位'),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('64位'),
                      ),
                    ],
                    selected: {is32Bit},
                    onSelectionChanged: (Set<bool> selected) {
                      setState(() => is32Bit = selected.first);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 模块选择卡片
  Widget _buildModuleCard() {
    final appConfig = context.watch<AppConfig>();
    final selectedModules = appConfig.selectedModules;
    final hasPackageName = appConfig.selectedPackageName != null;

    // 按模块名称分组统计
    final groupedModules = <String, int>{};
    for (var module in selectedModules) {
      groupedModules[module.name] = (groupedModules[module.name] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.code, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('扫描模块', style: Theme.of(context).textTheme.titleMedium),
                ),
                // 显示模块来源标记
                if (hasPackageName)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '已保存',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                // 已选数量
                if (selectedModules.isNotEmpty)
                  Badge(
                    label: Text('${selectedModules.length}'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 点击配置区域
            InkWell(
              onTap: openModuleSelector,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: groupedModules.isEmpty
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('点击配置扫描模块', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ],
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groupedModules.entries.map((entry) {
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              radius: 12,
                              child: Text(
                                '${entry.value}',
                                style: const TextStyle(fontSize: 10, color: Colors.white),
                              ),
                            ),
                            label: Text(entry.key),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              final appConfig = context.read<AppConfig>();
                              final currentModules = List<ModuleItem>.from(appConfig.selectedModules);
                              currentModules.removeWhere((m) => m.name == entry.key);
                              appConfig.setSelectedModules(currentModules);
                              // 保存到本地
                              if (appConfig.selectedPackageName != null) {
                                appConfig.saveModulesForPackage(
                                  appConfig.selectedPackageName,
                                  currentModules,
                                );
                              }
                            },
                          );
                        }).toList(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 文件选择卡片
  Widget _buildFileCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.folder_open, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('扫描数据', style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 格式文件
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.transform, color: Theme.of(context).colorScheme.primary),
              title: const Text('格式文件'),
              subtitle: Text(
                '转换扫描数据格式',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.push('/format');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 高级选项卡片
  Widget _buildAdvancedCard() {
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
        title: Text('高级选项', style: Theme.of(context).textTheme.titleMedium),
        children: [
          // 扫描核心（最上面）
          ListTile(
            title: const Text('扫描核心'),
            trailing: Text('$scanCores 核', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editCores,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 处理 0xb4000000（暂未实现）
          SwitchListTile(
            title: Row(
              children: [
                const Text('处理 0xb4000000'),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '暂未实现',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: const Text('处理 Android 特殊内存地址'),
            value: false,
            onChanged: null,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 4字节对齐（暂未实现）
          SwitchListTile(
            title: Row(
              children: [
                const Text('4字节对齐'),
                const SizedBox(width: 4),
                _buildHelpIcon('4字节对齐说明', 'GG修改器默认是4字节对齐（地址 % 4 = 0）。\n\n'
                    '但 0x3 这种地址也是存在指针的，不建议开启。\n\n'
                    '大部分指针都是规则的4字节，如果找不到指针时可以尝试开启。'),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '暂未实现',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(byteAlignment ? '开启' : '关闭'),
            value: byteAlignment,
            onChanged: null,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 跨页处理（暂未实现）
          SwitchListTile(
            title: Row(
              children: [
                const Text('跨页处理'),
                const SizedBox(width: 4),
                _buildHelpIcon('跨页处理说明', '由于指针在 4096 字节的内存页边界被截断，导致扫描不出来。\n\n'
                    '默认不推荐开启。\n\n'
                    '场景：你的友人A分享了指针链条，你死活扫不出来这条，其他的可以，大概率是这个问题。'),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '暂未实现',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(pageAlignment ? '开启' : '关闭'),
            value: pageAlignment,
            onChanged: null,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 模块扩展（暂未实现）
          SwitchListTile(
            title: Row(
              children: [
                const Text('模块扩展'),
                const SizedBox(width: 4),
                _buildHelpIcon('模块扩展说明', '开启后处理腾讯游戏对模块单独处理导致模块 index 变多的问题。\n\n'
                    '部分 index 是随机的，开启后有一定解决能力。\n\n'
                    '如果没有特别需要，不建议开启。'),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '暂未实现',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(moduleExtension ? '开启' : '关闭'),
            value: moduleExtension,
            onChanged: null,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 负偏移（暂未实现）
          SwitchListTile(
            title: Row(
              children: [
                const Text('负偏移'),
                const SizedBox(width: 4),
                _buildHelpIcon('负偏移说明', '可以增加指针链条输出量。\n\n'
                    '场景：支持反向查找指针链条\n'
                    '例如：libUE4.so[Cd][1]+0xffff-0x28+0x24-0x4\n\n'
                    '开启后可以搜索负数偏移的指针。'),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '暂未实现',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(negativeOffset ? '开启' : '关闭'),
            value: negativeOffset,
            onChanged: null,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 缺页处理
          SwitchListTile(
            title: Row(
              children: [
                const Text('缺页处理'),
                const SizedBox(width: 4),
                _buildHelpIcon('缺页处理说明', '不建议开启！\n\n'
                    '缺页会导致大部分内存页面被跳过，导致获取不到指针。\n\n'
                    '尽量使用自定义读写对接内核过掉搜索检测。'),
              ],
            ),
            subtitle: Text(handlePageFault ? '开启' : '关闭'),
            value: handlePageFault,
            onChanged: (v) {
              if (v) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('提示'),
                    content: const Text('缺页处理不建议开启！\n\n'
                        '缺页会导致大部分内存页面被跳过，导致获取不到指针。\n\n'
                        '尽量使用自定义读写对接内核过掉搜索检测。\n\n'
                        '确定要开启吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () {
                          setState(() => handlePageFault = true);
                          Navigator.pop(context);
                        },
                        child: const Text('确定开启'),
                      ),
                    ],
                  ),
                );
              } else {
                setState(() => handlePageFault = false);
              }
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 读取受限内存（需要PREAD64或CUSTOM）
          SwitchListTile(
            title: Row(
              children: [
                const Text('读取受限内存'),
                const SizedBox(width: 4),
                _buildHelpIcon('读取受限内存说明', '需要PREAD64或CUSTOM读写方式。\n\n'
                    'SYSCALL不支持此功能。\n\n'
                    '强制读取被保护的内存段，某些内存区域被系统保护，正常情况下无法读取。'),
              ],
            ),
            subtitle: Text(
              readProtected ? '开启' : '关闭',
              style: TextStyle(
                color: context.watch<AppConfig>().canReadProtected
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            value: readProtected,
            onChanged: context.watch<AppConfig>().canReadProtected
                ? (v) => setState(() => readProtected = v)
                : null,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 数据格式（最下面）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Row(
                  children: [
                    const Text('数据格式'),
                    const SizedBox(width: 4),
                    _buildHelpIcon('数据格式说明', '通用格式：一般情况下数据量较小，兼容性好。\n\n'
                        '暴力格式：只能使用暴力对比，对比速度大幅加快。但指针对比精度不够，会产生垃圾指针，需要反复筛选过滤。\n\n'
                        '建议：优先使用通用格式，只有在通用格式找不到或需要快速扫描时才使用暴力格式。'),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 180,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('通用'),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('暴力'),
                      ),
                    ],
                    selected: {isBrutalMode},
                    onSelectionChanged: (Set<bool> selected) async {
                      final newIsBrutal = selected.first;
                      // 切换格式时重新获取输出文件路径
                      if (newIsBrutal != isBrutalMode) {
                        setState(() => isBrutalMode = newIsBrutal);
                        // 重新生成输出路径（通用用out，暴力用norm）
                        await _generateOutputPath();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 操作按钮
  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: startScan,
        icon: const Icon(Icons.play_arrow),
        label: const Text('开始扫描'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Cd': return Colors.blue;
      case 'Cb': return Colors.green;
      case 'Xa': return Colors.orange;
      default: return Colors.grey;
    }
  }

  // === 编辑方法 ===

  /// 生成输出路径
  Future<void> _generateOutputPath() async {
    final appConfig = context.read<AppConfig>();
    final wsService = context.read<WsService>();

    // 确定目录：如果有选中的包名，则使用扫描数据路径+包名
    String dir = appConfig.dataPath;
    if (appConfig.selectedPackageName != null) {
      dir = '$dir/${appConfig.selectedPackageName}';
    }

    // 根据数据格式选择扩展名：通用用out，暴力用norm
    final extension = isBrutalMode ? 'norm' : 'out';

    // 调用获取下一个文件路径
    final path = await wsService.getNextFile(dir, extension);

    if (path != null && mounted) {
      final fileName = path.split('/').last;
      setState(() {
        outputPath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('输出路径已生成: $fileName'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      logger.info('ScanScreen', '输出路径已生成: $path');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('生成输出路径失败，请检查路径配置'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void editAddress() {
    final controller = TextEditingController();
    List<String> tempList = List.from(searchAddresses);
    String? errorMessage;
    Timer? debounceTimer;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            final is64Bit = !is32Bit;
            final hintText = is64Bit ? 'FFFFFFFFFFFFFFFF' : 'FFFFFFFF';
            final maxValue = is64Bit
                ? 'FFFFFFFFFFFFFFFF'
                : 'FFFFFFFF';

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.location_on),
                  const SizedBox(width: 8),
                  const Text('目标地址'),
                  const Spacer(),
                  Text(
                    is64Bit ? '64位' : '32位',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 已添加的地址列表
                    if (tempList.isNotEmpty) ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: tempList.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 12,
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(fontSize: 10, color: Colors.white),
                                ),
                              ),
                              title: Text(
                                tempList[index],
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setDialog(() => tempList.removeAt(index)),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 地址输入框
                    TextField(
                      controller: controller,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(
                          fontFamily: 'monospace',
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        prefixText: '0x ',
                        prefixStyle: TextStyle(
                          fontFamily: 'monospace',
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        errorText: errorMessage,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        // 防抖：延迟 300ms 清除错误提示
                        debounceTimer?.cancel();
                        debounceTimer = Timer(const Duration(milliseconds: 300), () {
                          if (errorMessage != null) {
                            setDialog(() => errorMessage = null);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    // 添加按钮
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          String addr = controller.text.trim().toUpperCase();
                          if (addr.isEmpty) {
                            setDialog(() => errorMessage = '请输入地址');
                            return;
                          }

                          // 验证是否为有效十六进制
                          if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(addr)) {
                            setDialog(() => errorMessage = '地址格式错误，仅支持十六进制');
                            return;
                          }

                          // 验证地址范围（使用字符串比较避免整数溢出）
                          final addrUpper = addr.toUpperCase();
                          final maxUpper = maxValue.toUpperCase();
                          if (addrUpper.length > maxUpper.length ||
                              (addrUpper.length == maxUpper.length && addrUpper.compareTo(maxUpper) > 0)) {
                            setDialog(() => errorMessage = '地址超出范围');
                            return;
                          }

                          setDialog(() {
                            tempList.add('0x$addr');
                            controller.clear();
                            errorMessage = null;
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('添加'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (tempList.isNotEmpty)
                  TextButton(
                    onPressed: () => setDialog(() => tempList.clear()),
                    child: const Text('清空全部'),
                  ),
                TextButton(
                  onPressed: () {
                    debounceTimer?.cancel();
                    Navigator.pop(context);
                  },
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    debounceTimer?.cancel();
                    setState(() => searchAddresses = tempList);
                    Navigator.pop(context);
                  },
                  child: Text('确定 (${tempList.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void editLevel() {
    final controller = TextEditingController(text: '$scanLevel');
    int temp = scanLevel;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('扫描层级'),
            content: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(28),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: temp > 1
                        ? () {
                            setDialog(() {
                              temp--;
                              controller.text = '$temp';
                            });
                          }
                        : null,
                    icon: const Icon(Icons.remove, size: 20),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (value) {
                        final v = int.tryParse(value);
                        if (v != null) {
                          setDialog(() => temp = v);
                        }
                      },
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: temp < 20
                        ? () {
                            setDialog(() {
                              temp++;
                              controller.text = '$temp';
                            });
                          }
                        : null,
                    icon: const Icon(Icons.add, size: 20),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final v = int.tryParse(controller.text);
                  if (v == null || v < 1 || v > 20) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('层级范围：1-20')),
                    );
                    return;
                  }
                  setState(() => scanLevel = v);
                  Navigator.pop(context);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
  }

  void editRange() {
    // 解析当前值
    int currentValue = 2000; // 默认 0x7D0
    if (scanRange.startsWith('0x') || scanRange.startsWith('0X')) {
      currentValue = int.tryParse(scanRange.substring(2), radix: 16) ?? 2000;
    } else {
      currentValue = int.tryParse(scanRange) ?? 2000;
    }

    final decController = TextEditingController(text: '$currentValue');
    final hexController = TextEditingController(text: currentValue.toRadixString(16).toUpperCase());

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Row(
              children: [
                const Text('扫描范围'),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.help_outline, color: Theme.of(context).colorScheme.primary),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('扫描范围说明'),
                        content: const Text(
                          '扫描范围用于限制搜索结果的偏移量。\n\n'
                          '⚠️ 注意：GG修改器中的指针搜索值 2048 实际上是十六进制的 0x2048（即十进制 8264）。\n\n'
                          '一般情况下，我们使用十进制进行搜索，请注意甄别。',
                        ),
                        actions: [
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 十进制输入
                TextField(
                  controller: decController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '十进制',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final v = int.tryParse(value);
                    if (v != null) {
                      hexController.text = v.toRadixString(16).toUpperCase();
                    }
                  },
                ),
                const SizedBox(height: 16),
                // 十六进制输入
                TextField(
                  controller: hexController,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: '十六进制',
                    prefixText: '0x ',
                    prefixStyle: TextStyle(
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (value) {
                    final v = int.tryParse(value, radix: 16);
                    if (v != null) {
                      decController.text = '$v';
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final v = int.tryParse(decController.text);
                  if (v == null || v <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入有效的范围值')),
                    );
                    return;
                  }
                  setState(() => scanRange = '0x${v.toRadixString(16).toUpperCase()}');
                  Navigator.pop(context);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
  }

  void openModuleSelector() async {
    final appConfig = context.read<AppConfig>();
    final currentPackageName = appConfig.selectedPackageName;

    // 如果没有选中包名，提示用户先选择
    if (currentPackageName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先在基础配置中选择进程包名'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 临时选中列表（用户之前选中的模块）
    List<ModuleItem> tempSelected = List<ModuleItem>.from(appConfig.selectedModules);
    String searchText = '';
    bool isLoading = true;
    Function(VoidCallback)? setDialogState;

    if (!mounted) return;

    // 显示弹窗（先显示loading）
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            setDialogState = setDialog;

            // 筛选模块
            final filteredModules = appConfig.availableModules.where((module) {
              return module.name.toLowerCase().contains(searchText.toLowerCase());
            }).toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Text('选择扫描模块'),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '将保存到本地',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    // 搜索框
                    TextField(
                      decoration: InputDecoration(
                        hintText: '搜索模块...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onChanged: (value) {
                        setDialog(() => searchText = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    // 已选数量
                    if (tempSelected.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 4),
                            Text('已选 ${tempSelected.length} 项', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                            const Spacer(),
                            TextButton(
                              onPressed: () => setDialog(() => tempSelected.clear()),
                              child: const Text('清空'),
                            ),
                          ],
                        ),
                      ),
                    // 模块列表或Loading
                    Expanded(
                      child: isLoading
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('正在获取模块列表...'),
                                ],
                              ),
                            )
                          : (filteredModules.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.extension_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      const SizedBox(height: 16),
                                      Text('暂无模块数据', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                      const SizedBox(height: 8),
                                      Text('请确保已连接服务器并选择进程', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filteredModules.length,
                                  itemBuilder: (context, index) {
                                    final module = filteredModules[index];
                                    final isSelected = tempSelected.contains(module);
                                    return CheckboxListTile(
                                      value: isSelected,
                                      onChanged: (selected) {
                                        setDialog(() {
                                          if (selected == true) {
                                            tempSelected.add(module);
                                          } else {
                                            tempSelected.remove(module);
                                          }
                                        });
                                      },
                                      title: Text(module.name, style: const TextStyle(fontFamily: 'monospace')),
                                      subtitle: Text('${module.type} | ${module.startAddress} ~ ${module.endAddress}'),
                                      secondary: CircleAvatar(
                                        backgroundColor: _getTypeColor(module.type),
                                        radius: 12,
                                        child: Text(
                                          module.type,
                                          style: const TextStyle(color: Colors.white, fontSize: 10),
                                        ),
                                      ),
                                    );
                                  },
                                )),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    // 更新 AppConfig 中的模块
                    appConfig.setSelectedModules(tempSelected);

                    // 保存到本地文件
                    appConfig.saveModulesForPackage(
                      currentPackageName,
                      tempSelected,
                    );

                    setState(() {});
                    Navigator.pop(context);
                  },
                  child: Text('确定 (${tempSelected.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    // 弹窗显示后，加载数据并更新UI
    try {
      final wsService = context.read<WsService>();
      await appConfig.fetchAndLoadModules(wsService, currentPackageName);
    } catch (e) {
      logger.error('ScanScreen', '加载模块失败', e);
    } finally {
      // 更新loading状态，显示模块列表
      if (mounted && setDialogState != null) {
        setDialogState!(() {
          isLoading = false;
        });
      }
    }
  }

  void editCores() {
    final controller = TextEditingController(text: '$scanCores');
    int temp = scanCores;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('扫描核心'),
            content: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(28),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: temp > 1
                        ? () {
                            setDialog(() {
                              temp--;
                              controller.text = '$temp';
                            });
                          }
                        : null,
                    icon: const Icon(Icons.remove, size: 20),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (value) {
                        final v = int.tryParse(value);
                        if (v != null) {
                          setDialog(() => temp = v);
                        }
                      },
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: temp < 16
                        ? () {
                            setDialog(() {
                              temp++;
                              controller.text = '$temp';
                            });
                          }
                        : null,
                    icon: const Icon(Icons.add, size: 20),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final v = int.tryParse(controller.text);
                  if (v == null || v < 1 || v > 16) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('核心范围：1-16')),
                    );
                    return;
                  }
                  setState(() => scanCores = v);
                  Navigator.pop(context);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHelpIcon(String title, String content) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      },
      child: Icon(
        Icons.help_outline,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  /// 开始扫描
  Future<void> startScan() async {
    if (searchAddresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置目标地址')),
      );
      return;
    }

    final appConfig = context.read<AppConfig>();
    final wsService = context.read<WsService>();

    // 检查WebSocket连接
    if (!wsService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接到服务器')),
      );
      return;
    }

    // 构建扫描参数 - 与core-fs中的memsetting枚举匹配
    final ranges = <String>[];
    if (memoryRanges['Anonymous'] == true) ranges.add('Anonymous');
    if (memoryRanges['C_alloc'] == true) ranges.add('C_alloc');
    if (memoryRanges['C_data'] == true) ranges.add('C_data');
    if (memoryRanges['C_bss'] == true) ranges.add('C_bss');
    if (memoryRanges['C_heap'] == true) ranges.add('C_heap');
    if (memoryRanges['Java_heap'] == true) ranges.add('Java_heap');
    if (memoryRanges['Java'] == true) ranges.add('Java');
    if (memoryRanges['Stack'] == true) ranges.add('Stack');
    if (memoryRanges['Video'] == true) ranges.add('Video');
    if (memoryRanges['Code_app'] == true) ranges.add('Code_app');
    if (memoryRanges['Code_system'] == true) ranges.add('Code_system');
    if (memoryRanges['Ashmem'] == true) ranges.add('Ashmem');
    if (memoryRanges['Other'] == true) ranges.add('Other');
    if (memoryRanges['Bad'] == true) ranges.add('Bad');
    if (memoryRanges['PPSSPP'] == true) ranges.add('PPSSPP');

    // 启动扫描
    final taskId = await wsService.startScan(
      packageName: appConfig.selectedPackageName,
      pid: appConfig.selectedPid,
      addresses: searchAddresses,
      depth: scanLevel,
      offset: int.tryParse(scanRange.replaceAll('0x', ''), radix: 16) ?? 0x7D0,
      outputFile: outputPath,
      count: scanCores,
      size: 1 << 20,
      ranges: ranges,
      brutalMode: isBrutalMode,
      pageFault: handlePageFault,
      handleB4000000: handleB4000000,
    );

    if (taskId != null && mounted) {
      setState(() {
        _currentTaskId = taskId;
        _showTerminal = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('扫描已启动'),
          duration: Duration(seconds: 1),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('启动扫描失败')),
      );
    }
  }

  /// 格式化范围显示：0x7D0 / 2000
  String _formatRangeDisplay(String range) {
    int decValue;
    if (range.startsWith('0x') || range.startsWith('0X')) {
      decValue = int.tryParse(range.substring(2), radix: 16) ?? 0;
    } else {
      decValue = int.tryParse(range) ?? 0;
    }
    final hexStr = decValue.toRadixString(16).toUpperCase();
    return '0x$hexStr / $decValue';
  }
}

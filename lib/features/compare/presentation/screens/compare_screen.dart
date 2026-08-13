import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fscan/core/config/app_config.dart';
import 'package:fscan/core/services/kami_service.dart';
import 'package:fscan/core/network/ws_service.dart';
import 'package:fscan/core/utils/logger.dart';
import 'package:fscan/shared/widgets/terminal_panel.dart';

/// 对比模式枚举
enum CompareMode {
  basic,    // 基础对比 (-m text)
  fast,     // 极速对比 (-m bin)
  brutal,   // 暴力对比 (compare-norm)
}

/// 文件数据模型
class CompareFile {
  final String name;
  final String path;
  final int size;
  final String modified;
  final String extension;
  final String? arch;  // out/bin 文件才有 arch

  CompareFile({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    required this.extension,
    this.arch,
  });

  factory CompareFile.fromJson(Map<String, dynamic> json) {
    return CompareFile(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      size: json['size'] ?? 0,
      modified: json['modified'] ?? '',
      extension: json['extension'] ?? '',
      arch: json['arch'],
    );
  }

  String get sizeText {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 基址对比页面 - MD3 风格
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  // 对比模式
  CompareMode compareMode = CompareMode.basic;

  // 配置参数
  String levelLimit = '无限制';
  String maxDbNum = '无限制';
  int threadNum = 8;
  bool indexCheck = true;
  int nopLevel = 0;
  bool matchOptimize = true; // 匹配优化，极速对比专用
  bool is32Bit = false; // 进程位数
  String outputPath = '/storage/emulated/0/fscan/a1.txt';

  // 每个模式独立的文件选择列表
  final Map<CompareMode, List<CompareFile>> _selectedFilesByMode = {
    CompareMode.basic: [],
    CompareMode.fast: [],
    CompareMode.brutal: [],
  };

  // 当前模式选中的文件
  List<CompareFile> get selectedFiles => _selectedFilesByMode[compareMode] ?? [];

  // 文件相关
  List<CompareFile> availableFiles = [];

  // 每个模式独立的终端状态
  final Map<CompareMode, String?> _taskIdByMode = {
    CompareMode.basic: null,
    CompareMode.fast: null,
    CompareMode.brutal: null,
  };
  final Map<CompareMode, bool> _showTerminalByMode = {
    CompareMode.basic: false,
    CompareMode.fast: false,
    CompareMode.brutal: false,
  };

  // 每个模式独立的终端面板
  final Map<CompareMode, Widget?> _terminalPanels = {};

  // 当前模式支持的最大文件数
  int get maxFileCount {
    switch (compareMode) {
      case CompareMode.basic:
      case CompareMode.fast:
      case CompareMode.brutal:
        return 2;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFiles();
      _generateOutputPath();  // 初始化时生成输出路径
    });
  }

  /// 加载文件列表
  Future<void> _loadFiles() async {
    if (!mounted) return;

    try {
      final wsService = context.read<WsService>();
      final appConfig = context.read<AppConfig>();

      // 确定目录：如果有选中的包名，则使用扫描数据路径+包名
      String dir = appConfig.dataPath;
      if (appConfig.selectedPackageName != null) {
        dir = '$dir/${appConfig.selectedPackageName}';
      }

      // 根据模式加载不同类型的文件
      // 基础对比/极速对比: 输入 .out 文件 (扫描输出)
      // 暴力对比: 输入 .norm 文件 (扫描输出)
      List<String> extensions;
      switch (compareMode) {
        case CompareMode.basic:
        case CompareMode.fast:
          extensions = ['out'];
          break;
        case CompareMode.brutal:
          extensions = ['norm'];
          break;
      }
      final files = await wsService.getFiles(dir, extensions);

      if (files != null && mounted) {
        setState(() {
          availableFiles = files.map((f) => CompareFile.fromJson(f)).toList();
        });
      }
    } catch (e) {
      // 加载失败，保持当前状态
    }
  }

  /// 生成输出路径
  Future<void> _generateOutputPath() async {
    final appConfig = context.read<AppConfig>();
    final wsService = context.read<WsService>();

    // 确定目录：如果有选中的包名，则使用扫描数据路径+包名
    String dir = appConfig.dataPath;
    if (appConfig.selectedPackageName != null) {
      dir = '$dir/${appConfig.selectedPackageName}';
    }

    // 根据对比模式选择扩展名
    // 基础对比: txt, 极速对比: out, 暴力对比: norm
    String extension;
    switch (compareMode) {
      case CompareMode.basic:
        extension = 'txt';
        break;
      case CompareMode.fast:
        extension = 'out';
        break;
      case CompareMode.brutal:
        extension = 'norm';
        break;
    }

    // 调用获取下一个文件路径
    final path = await wsService.getNextFile(dir, extension);

    if (path != null && mounted) {
      setState(() {
        outputPath = path;
      });
      logger.info('CompareScreen', '输出路径已生成: $path');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基址对比'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 对比模式选择
            _buildModeCard(),
            const SizedBox(height: 16),

            // 对比配置
            _buildConfigCard(),
            const SizedBox(height: 16),

            // 文件选择
            _buildFileCard(),
            const SizedBox(height: 16),

            // 操作按钮
            _buildActionButtons(),

            // 终端面板（所有模式的面板都保留在树中，用 Offstage 控制显示/隐藏）
            ...CompareMode.values.map((mode) {
              final isCurrentMode = mode == compareMode;
              final showTerminal = _showTerminalByMode[mode] ?? false;
              final hasTask = _taskIdByMode[mode] != null;
              final shouldShow = isCurrentMode && showTerminal && hasTask;

              return Offstage(
                offstage: !shouldShow,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildTerminalCardForMode(mode),
                  ],
                ),
              );
            }),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 对比模式卡片
  Widget _buildModeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('对比模式', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 4),
                _buildHelpIcon('对比模式说明', '基础对比：输出文本格式，功能最多，但是速度会慢一些。\n\n'
                    '极速对比：输出二进制格式，最快，但是舍弃了到指针地址级别的判断。\n\n'
                    '暴力对比：对比 .norm 归一化文件，速度最快但精度较低，需要反复筛选。'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<CompareMode>(
                segments: const [
                  ButtonSegment(
                    value: CompareMode.basic,
                    label: Text('基础对比'),
                  ),
                  ButtonSegment(
                    value: CompareMode.fast,
                    label: Text('极速对比'),
                  ),
                  ButtonSegment(
                    value: CompareMode.brutal,
                    label: Text('暴力对比'),
                  ),
                ],
                selected: {compareMode},
                onSelectionChanged: (Set<CompareMode> selected) async {
                  final newMode = selected.first;
                  if (newMode != compareMode) {
                    setState(() {
                      compareMode = newMode;
                    });
                    // 切换模式时刷新输出路径
                    await _generateOutputPath();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 对比配置卡片
  Widget _buildConfigCard() {
    final isBrutal = compareMode == CompareMode.brutal;

    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('对比配置', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),

          // 层级限制 - 所有模式都有
          ListTile(
            title: const Text('层级限制'),
            trailing: Text(_formatLevelLimit(levelLimit), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editLevelLimit,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 限制数量 - 基础对比和极速对比
          if (!isBrutal) ...[
            ListTile(
              title: const Text('限制数量'),
              trailing: Text(_formatMaxDbNum(maxDbNum), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              onTap: editMaxDbNum,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],

          // 输出路径
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

          // 进程位数 - 基础对比和极速对比
          if (!isBrutal) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                        setState(() {
                          is32Bit = selected.first;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 文件选择卡片
  Widget _buildFileCard() {
    // 根据对比模式确定文件扩展名提示
    String fileHint;
    switch (compareMode) {
      case CompareMode.basic:
        fileHint = '.out';
        break;
      case CompareMode.fast:
        fileHint = '.out';
        break;
      case CompareMode.brutal:
        fileHint = '.norm';
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('选择文件', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (selectedFiles.isNotEmpty)
                  Badge(
                    label: Text('${selectedFiles.length}/$maxFileCount'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 文件选择区域
            InkWell(
              onTap: selectFiles,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  minHeight: selectedFiles.isEmpty ? 56 : 0,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: selectedFiles.isEmpty
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('点击选择 $fileHint 文件', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ],
                      )
                    : Column(
                        children: selectedFiles.asMap().entries.map((entry) {
                          final index = entry.key;
                          final file = entry.value;
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: index < selectedFiles.length - 1
                                ? BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                                      ),
                                    ),
                                  )
                                : null,
                            child: Row(
                              children: [
                                // 序号
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(fontSize: 10, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // 文件名
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        file.name,
                                        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        file.arch != null
                                            ? '${file.arch} | ${file.sizeText} | ${file.modified}'
                                            : '${file.sizeText} | ${file.modified}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 删除按钮
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _selectedFilesByMode[compareMode]?.remove(file);
                                    });
                                  },
                                ),
                              ],
                            ),
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

  /// 操作按钮
  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: startCompare,
        icon: const Icon(Icons.play_arrow),
        label: const Text('开始对比'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  /// 为指定模式构建终端面板卡片
  Widget _buildTerminalCardForMode(CompareMode mode) {
    // 获取当前模式的终端面板，如果不存在则创建一个新的
    final existingPanel = _terminalPanels[mode];
    final terminalPanel = existingPanel ?? TerminalPanel(
      key: ValueKey('terminal_${mode}_${_taskIdByMode[mode]}'),
      taskId: _taskIdByMode[mode],
      onComplete: () {
        // 对比完成后自动刷新输出路径
        if (mode == compareMode) {
          _generateOutputPath();
        }
      },
    );

    // 保存新创建的面板
    if (existingPanel == null) {
      _terminalPanels[mode] = terminalPanel;
    }

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
                      _showTerminalByMode[mode] = false;
                      _taskIdByMode[mode] = null;
                      _terminalPanels[mode] = null;
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
            child: terminalPanel,
          ),
        ],
      ),
    );
  }

  /// 编辑层级限制
  void editLevelLimit() {
    // 解析当前值
    int? startLevel;
    int? endLevel;
    if (levelLimit != '无限制') {
      final parts = levelLimit.split('-');
      startLevel = int.tryParse(parts[0]);
      if (parts.length > 1) {
        endLevel = int.tryParse(parts[1]);
      }
    }

    final startController = TextEditingController(text: startLevel?.toString() ?? '0');
    final endController = TextEditingController(text: endLevel?.toString() ?? '0');
    bool showEnd = endLevel != null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('层级限制'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 起始层级
                if (!showEnd)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: () => setDialog(() => showEnd = true),
                        icon: const Icon(Icons.add, size: 20),
                      ),
                    ],
                  ),

                // 结束层级（点击+后显示）
                if (showEnd)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('~', style: Theme.of(context).textTheme.titleLarge),
                      ),
                      Expanded(
                        child: TextField(
                          controller: endController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: () => setDialog(() {
                          showEnd = false;
                          endController.clear();
                        }),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() => levelLimit = '无限制');
                  Navigator.pop(context);
                },
                child: const Text('无限制'),
              ),
              FilledButton(
                onPressed: () {
                  final start = startController.text.trim();
                  final end = endController.text.trim();

                  if (start.isEmpty && end.isEmpty) {
                    setState(() => levelLimit = '无限制');
                    Navigator.pop(context);
                  } else if (start.isNotEmpty && end.isEmpty) {
                    setState(() => levelLimit = start);
                    Navigator.pop(context);
                  } else if (start.isNotEmpty && end.isNotEmpty) {
                    final startVal = int.tryParse(start) ?? 0;
                    final endVal = int.tryParse(end) ?? 0;
                    if (endVal < startVal) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('结束层级不能小于起始层级')),
                      );
                      return;
                    }
                    setState(() => levelLimit = '$start-$end');
                    Navigator.pop(context);
                  }
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 编辑限制数量
  void editMaxDbNum() {
    final controller = TextEditingController(
      text: maxDbNum == '无限制' ? '' : maxDbNum,
    );
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('限制数量'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 常用选项
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    {'label': '无限制', 'value': '无限制'},
                    {'label': '1k', 'value': '1000'},
                    {'label': '1w', 'value': '10000'},
                    {'label': '10w', 'value': '100000'},
                    {'label': '100w', 'value': '1000000'},
                    {'label': '1亿', 'value': '100000000'},
                    {'label': '3亿', 'value': '300000000'},
                  ].map((item) {
                    final isSelected = maxDbNum == item['value'];
                    return ChoiceChip(
                      labelStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      label: Text(item['label']!),
                      selected: isSelected,
                      onSelected: (_) {
                        setDialog(() {
                          maxDbNum = item['value']!;
                          controller.text = item['value'] == '无限制' ? '' : item['value']!;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // 自定义输入
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '不输入或0=无限制',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isEmpty || value == '0') {
                    setState(() => maxDbNum = '无限制');
                  } else {
                    setState(() => maxDbNum = value);
                  }
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

  /// 编辑线程数量
  void editThreadNum() {
    final controller = TextEditingController(text: '$threadNum');
    int temp = threadNum;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('线程数量'),
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
                      const SnackBar(content: Text('线程范围：1-16')),
                    );
                    return;
                  }
                  setState(() => threadNum = v);
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

  /// 编辑去除层级
  void editNopLevel() {
    final controller = TextEditingController(text: '$nopLevel');
    int temp = nopLevel;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('去除层级'),
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
                    onPressed: temp > 0
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
                    onPressed: temp < 10
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
                  if (v == null || v < 0 || v > 10) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('层级范围：0-10')),
                    );
                    return;
                  }
                  setState(() => nopLevel = v);
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

  /// 选择文件弹窗
  Future<void> selectFiles() async {
    List<CompareFile> tempSelected = List.from(selectedFiles);
    String searchText = '';
    Function(VoidCallback)? setDialogState;
    bool isLoading = true;

    if (!mounted) return;

    // 根据模式确定文件类型提示
    String fileTypeHint;
    switch (compareMode) {
      case CompareMode.basic:
        fileTypeHint = '基础对比 - 选择两个 .out 文件';
        break;
      case CompareMode.fast:
        fileTypeHint = '极速对比 - 选择两个 .out 文件';
        break;
      case CompareMode.brutal:
        fileTypeHint = '暴力对比 - 选择两个 .norm 文件';
        break;
    }

    // 先弹窗，显示加载中
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            setDialogState = setDialog;

            // 搜索筛选
            final filteredFiles = availableFiles.where((file) {
              return file.name.toLowerCase().contains(searchText.toLowerCase());
            }).toList();

            return AlertDialog(
              title: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('选择文件'),
                        Text(
                          fileTypeHint,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLoading)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        setDialog(() => isLoading = true);
                        await _loadFiles();
                        if (mounted) {
                          setDialog(() => isLoading = false);
                        }
                      },
                    ),
                  Text(
                    '${tempSelected.length}/$maxFileCount',
                    style: TextStyle(
                      fontSize: 14,
                      color: tempSelected.length >= maxFileCount
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在加载文件列表...'),
                          ],
                        ),
                      )
                    : filteredFiles.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.folder_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                const SizedBox(height: 16),
                                Text('暂无文件', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              // 搜索框
                              TextField(
                                decoration: InputDecoration(
                                  hintText: '搜索文件...',
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
                              // 文件列表
                              Expanded(
                                child: ListView.builder(
                                  itemCount: filteredFiles.length,
                                  itemBuilder: (context, index) {
                                    final file = filteredFiles[index];
                                    final isSelected = tempSelected.any((f) => f.path == file.path);
                                    final canSelect = tempSelected.length < maxFileCount || isSelected;
                                    final isNormFile = file.extension.toLowerCase() == 'norm';

                                    return ListTile(
                                      leading: Checkbox(
                                        value: isSelected,
                                        onChanged: canSelect
                                            ? (selected) {
                                                setDialog(() {
                                                  if (selected == true) {
                                                    tempSelected.add(file);
                                                  } else {
                                                    tempSelected.removeWhere((f) => f.path == file.path);
                                                  }
                                                });
                                              }
                                            : null,
                                      ),
                                      title: Text(file.name, style: const TextStyle(fontFamily: 'monospace')),
                                      subtitle: Text(file.arch != null
                                          ? '${file.arch} | ${file.sizeText} | ${file.modified}'
                                          : '${file.sizeText} | ${file.modified}'),
                                      trailing: isNormFile
                                          ? IconButton(
                                              icon: Icon(
                                                Icons.transform,
                                                size: 20,
                                                color: Theme.of(context).colorScheme.tertiary,
                                              ),
                                              tooltip: '转换为 .out',
                                              onPressed: () async {
                                                await _convertNormToOut(file, setDialog);
                                              },
                                            )
                                          : CircleAvatar(
                                              backgroundColor: Theme.of(context).colorScheme.primary,
                                              radius: 12,
                                              child: Text(
                                                file.extension.toUpperCase(),
                                                style: const TextStyle(fontSize: 10, color: Colors.white),
                                              ),
                                            ),
                                    );
                                  },
                                ),
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
                    setState(() {
                      _selectedFilesByMode[compareMode] = List.from(tempSelected);
                    });
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
      final appConfig = context.read<AppConfig>();

      String dir = appConfig.dataPath;
      if (appConfig.selectedPackageName != null) {
        dir = '$dir/${appConfig.selectedPackageName}';
      }

      List<String> extensions;
      switch (compareMode) {
        case CompareMode.basic:
        case CompareMode.fast:
          extensions = ['out'];
          break;
        case CompareMode.brutal:
          extensions = ['norm'];
          break;
      }

      final files = await wsService.getFiles(dir, extensions);
      if (files != null && mounted) {
        setState(() {
          availableFiles = files.map((f) => CompareFile.fromJson(f)).toList();
        });
      }
    } catch (e) {
      logger.error('CompareScreen', '加载文件失败', e);
    } finally {
      if (mounted && setDialogState != null) {
        setDialogState!(() {
          isLoading = false;
        });
      }
    }
  }

  /// 将 .norm 文件转换为 .out 文件
  Future<void> _convertNormToOut(CompareFile file, StateSetter? setDialog) async {
    if (!mounted) return;

    final wsService = context.read<WsService>();
    final kamiService = context.read<KamiService>();

    // 显示确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.transform, color: Theme.of(context).colorScheme.primary),
        title: const Text('转换为 .out'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('将以下文件转换为 .out 格式：'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                file.name,
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '转换后的文件将保存在同一目录下',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始转换'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 自动生成输出路径：将 .norm 替换为 .out
    final inputPath = file.path;
    final outputPath = inputPath.replaceAll('.norm', '.out');

    // 显示加载中
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('正在转换 ${file.name}...'),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );
    }

    try {
      final result = await wsService.toOut(
        inputFiles: [file.path],
        outputFile: outputPath,
        kamiKey: kamiService.kamiKey,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        if (result != null && result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ ${file.name} 转换成功'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          // 刷新文件列表
          _refreshFileList(setDialog);
        } else {
          final errorMsg = result?['stderr'] ?? result?['error'] ?? '未知错误';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✗ 转换失败: $errorMsg'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('转换失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 刷新文件列表
  Future<void> _refreshFileList(StateSetter? setDialog) async {
    try {
      final wsService = context.read<WsService>();
      final appConfig = context.read<AppConfig>();

      String dir = appConfig.dataPath;
      if (appConfig.selectedPackageName != null) {
        dir = '$dir/${appConfig.selectedPackageName}';
      }

      List<String> extensions;
      switch (compareMode) {
        case CompareMode.basic:
        case CompareMode.fast:
          extensions = ['out'];
          break;
        case CompareMode.brutal:
          extensions = ['norm'];
          break;
      }

      final files = await wsService.getFiles(dir, extensions);
      if (files != null && mounted) {
        setState(() {
          availableFiles = files.map((f) => CompareFile.fromJson(f)).toList();
        });

        // 更新弹窗状态
        if (setDialog != null) {
          setDialog(() {});
        }
      }
    } catch (e) {
      logger.error('CompareScreen', '刷新文件列表失败', e);
    }
  }

  /// 开始对比
  Future<void> startCompare() async {
    // 验证文件数量
    if (selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择至少2个文件')),
      );
      return;
    }

    if (selectedFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择至少2个文件')),
      );
      return;
    }

    if (selectedFiles.length > maxFileCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多选择 $maxFileCount 个文件')),
      );
      return;
    }

    // 检查输出路径是否已存在
    final wsService = context.read<WsService>();
    final kamiService = context.read<KamiService>();
    final fileExists = await wsService.checkFileExists(outputPath);
    if (fileExists && mounted) {
      final shouldRefresh = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('输出文件已存在'),
          content: Text('输出路径 ${outputPath.split('/').last} 已存在，是否刷新输出路径？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      );

      if (shouldRefresh == true) {
        await _generateOutputPath();
      } else {
        return;
      }
    }

    // 获取文件路径列表
    final inputPaths = selectedFiles.map((f) => f.path).toList();

    // 解析层级限制
    int? levelMin;
    int? levelMax;
    if (levelLimit != '无限制') {
      final parts = levelLimit.split('-');
      levelMin = int.tryParse(parts[0]);
      if (parts.length > 1) {
        levelMax = int.tryParse(parts[1]);
      } else {
        levelMax = levelMin;
      }
    }

    // 解析限制数量
    int? limit;
    if (maxDbNum != '无限制') {
      limit = int.tryParse(maxDbNum);
    }

    String? taskId;

    try {
      if (compareMode == CompareMode.brutal) {
        // 暴力对比 - 使用 compare-norm 命令
        taskId = await wsService.compareNormFiles(
          inputFiles: inputPaths,
          outputFile: outputPath,
          minLevel: levelMin,
          maxLevel: levelMax,
          kamiKey: kamiService.kamiKey,
        );
      } else {
        // 基础对比/极速对比 - 使用 compare 命令
        final mode = compareMode == CompareMode.basic ? 'text' : 'bin';
        taskId = await wsService.compareFiles(
          inputFiles: inputPaths,
          outputFile: outputPath,
          mode: mode,
          is32Bit: is32Bit,
          limit: limit,
          levelMin: levelMin,
          levelMax: levelMax,
          kamiKey: kamiService.kamiKey,
        );
      }

      if (taskId != null && mounted) {
        setState(() {
          _taskIdByMode[compareMode] = taskId;
          _showTerminalByMode[compareMode] = true;
          // 创建新的终端面板
          _terminalPanels[compareMode] = TerminalPanel(
            key: ValueKey('terminal_${compareMode}_$taskId'),
            taskId: taskId,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('对比任务已启动'),
            duration: Duration(seconds: 1),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('启动对比失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('对比失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 格式化层级限制显示
  String _formatLevelLimit(String limit) {
    if (limit == '无限制') return '无限制';
    if (limit.contains('-')) {
      final parts = limit.split('-');
      if (parts[0] == parts[1]) {
        return '${parts[0]}层';
      }
      return '${parts[0]}~${parts[1]}层';
    }
    return '$limit层';
  }

  String _formatMaxDbNum(String count) {
    if (count == '无限制') return '无限制';
    final value = int.tryParse(count) ?? 0;
    if (value >= 100000000) return '${value ~/ 100000000}亿';
    if (value >= 10000) return '${value ~/ 10000}w';
    if (value >= 1000) return '${value ~/ 1000}k';
    return count;
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
}

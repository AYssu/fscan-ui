import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:fscan/core/config/app_config.dart';
import 'package:fscan/core/network/ws_service.dart';
import 'package:fscan/core/utils/logger.dart';
import 'package:fscan/shared/widgets/terminal_panel.dart';

/// 过滤模式枚举
enum FilterMode {
  format, // 格式过滤
  text,   // 文本过滤
}

/// 输出格式枚举
enum OutputFormat {
  txt, // 文本格式
  bin, // 二进制格式
}

/// 文件数据模型
class FilterFile {
  final String name;
  final String path;
  final int size;
  final String modified;
  final String extension;
  final String? arch;

  FilterFile({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    required this.extension,
    this.arch,
  });

  factory FilterFile.fromJson(Map<String, dynamic> json) {
    return FilterFile(
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

  /// 获取不带扩展名的文件名
  String get nameWithoutExtension {
    final dotIndex = name.lastIndexOf('.');
    return dotIndex > 0 ? name.substring(0, dotIndex) : name;
  }
}

/// 过滤目标地址数据模型
class FilterTarget {
  final String address;
  final int count;
  final int d;
  final String f;

  FilterTarget({
    required this.address,
    required this.count,
    required this.d,
    required this.f,
  });

  factory FilterTarget.fromJson(Map<String, dynamic> json) {
    return FilterTarget(
      address: json['address'] ?? '',
      count: json['count'] ?? 0,
      d: json['d'] ?? 0,
      f: json['f'] ?? '0.0',
    );
  }
}

/// 基址过滤页面 - MD3 风格
class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  // 过滤模式
  FilterMode filterMode = FilterMode.format;

  // 输出格式
  OutputFormat outputFormat = OutputFormat.txt;

  // 配置参数
  bool is32Bit = false;

  // 每个模式独立的文件选择
  final Map<FilterMode, FilterFile?> _selectedFileByMode = {
    FilterMode.format: null,
    FilterMode.text: null,
  };

  // 每个模式独立的目标地址列表
  final Map<FilterMode, List<String>> _selectedTargetAddressesByMode = {
    FilterMode.format: [],
    FilterMode.text: [],
  };

  // 每个模式独立的目标地址数据
  final Map<FilterMode, List<FilterTarget>> _availableTargetsByMode = {
    FilterMode.format: [],
    FilterMode.text: [],
  };

  // 文件相关
  List<FilterFile> availableFiles = [];

  // 目标地址相关
  bool _isLoadingTargets = false;

  // 当前模式的文件选择
  FilterFile? get selectedFile => _selectedFileByMode[filterMode];
  set selectedFile(FilterFile? file) => _selectedFileByMode[filterMode] = file;

  // 当前模式的目标地址列表
  List<String> get selectedTargetAddresses => _selectedTargetAddressesByMode[filterMode] ?? [];
  set selectedTargetAddresses(List<String> addresses) => _selectedTargetAddressesByMode[filterMode] = addresses;

  // 当前模式的目标地址数据
  List<FilterTarget> get availableTargets => _availableTargetsByMode[filterMode] ?? [];
  set availableTargets(List<FilterTarget> targets) => _availableTargetsByMode[filterMode] = targets;

  // 目标地址输入控制器
  final TextEditingController _targetController = TextEditingController();

  // 每个模式独立的输出路径
  final Map<FilterMode, String> _outputPathByMode = {
    FilterMode.format: '',
    FilterMode.text: '',
  };

  // 当前模式的输出路径
  String get _outputPath => _outputPathByMode[filterMode] ?? '';
  set _outputPath(String path) => _outputPathByMode[filterMode] = path;

  // 每个模式独立的终端状态
  final Map<FilterMode, String?> _taskIdByMode = {
    FilterMode.format: null,
    FilterMode.text: null,
  };
  final Map<FilterMode, bool> _showTerminalByMode = {
    FilterMode.format: false,
    FilterMode.text: false,
  };
  final Map<FilterMode, Widget?> _terminalPanels = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFiles();
      // 如果有默认文件，更新输出路径
      if (selectedFile != null) {
        _updateOutputPath();
      }
    });
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  /// 获取数据目录
  String get _dataDir {
    final appConfig = context.read<AppConfig>();
    String dir = appConfig.dataPath;
    if (appConfig.selectedPackageName != null) {
      dir = '$dir/${appConfig.selectedPackageName}';
    }
    return dir;
  }

  /// 获取输出路径（带过滤编号）
  Future<String> _getOutputPath() async {
    if (selectedFile == null) return '';

    final dir = _dataDir;
    final wsService = context.read<WsService>();

    // 确定扩展名
    String ext;
    switch (filterMode) {
      case FilterMode.format:
        ext = outputFormat == OutputFormat.txt ? 'txt' : 'out';
        break;
      case FilterMode.text:
        ext = 'txt';
        break;
    }

    // 提取基础名称（移除已有的 [过滤N] 后缀）
    String baseName = selectedFile!.nameWithoutExtension;
    final filterPattern = RegExp(r'\[过滤\d+\]$');
    baseName = baseName.replaceAll(filterPattern, '');

    // 获取目录下的所有文件
    final files = await wsService.getFiles(dir, [ext]);
    final existingFiles = files?.map((f) => f['name'] as String).toList() ?? [];

    // 查找合适的编号
    int filterNum = 1;
    String outputPath;
    do {
      outputPath = '$dir/$baseName[过滤$filterNum].$ext';
      final fileName = '$baseName[过滤$filterNum].$ext';
      if (!existingFiles.contains(fileName)) {
        break;
      }
      filterNum++;
    } while (true);

    return outputPath;
  }

  /// 更新输出路径
  Future<void> _updateOutputPath() async {
    final path = await _getOutputPath();
    if (mounted) {
      setState(() {
        _outputPath = path;
      });
    }
  }

  /// 加载文件列表
  Future<void> _loadFiles() async {
    if (!mounted) return;

    try {
      final wsService = context.read<WsService>();
      final dir = _dataDir;

      // 根据模式加载不同类型的文件
      List<String> extensions;
      switch (filterMode) {
        case FilterMode.format:
          extensions = ['out', 'bin'];
          break;
        case FilterMode.text:
          extensions = ['txt'];
          break;
      }

      final files = await wsService.getFiles(dir, extensions);

      if (files != null && mounted) {
        setState(() {
          availableFiles = files.map((f) => FilterFile.fromJson(f)).toList();
        });
      }
    } catch (e) {
      // 加载失败，保持当前状态
    }
  }

  /// 加载目标地址列表
  Future<void> _loadTargets() async {
    if (selectedFile == null) return;

    setState(() => _isLoadingTargets = true);

    try {
      final wsService = context.read<WsService>();
      final appConfig = context.read<AppConfig>();

      // 获取当前进程 PID
      final pid = appConfig.selectedPid ?? 0;
      if (pid <= 0) {
        setState(() => _isLoadingTargets = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先选择目标进程')),
          );
        }
        return;
      }

      // 确定输入模式
      String mode;
      switch (selectedFile!.extension) {
        case 'txt':
          mode = 'text';
          break;
        default:
          mode = 'bin';
          break;
      }

      final result = await wsService.filterListTargets(
        inputFile: selectedFile!.path,
        mode: mode,
        is32Bit: is32Bit,
        pid: pid,
      );

      if (result != null && mounted) {
        if (result['success'] == true) {
          final targets = (result['targets'] as List?)
              ?.map((t) => FilterTarget.fromJson(t))
              .toList() ?? [];

          setState(() {
            availableTargets = targets;
            _isLoadingTargets = false;
          });

          // 显示地址选择弹窗
          _showTargetSelectionDialog();
        } else {
          setState(() => _isLoadingTargets = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('加载失败: ${result['error'] ?? '未知错误'}')),
            );
          }
        }
      } else if (mounted) {
        setState(() => _isLoadingTargets = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载目标地址失败')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTargets = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  /// 添加目标地址（手动输入）
  void _addTargetAddress(String address) {
    if (address.isEmpty) return;

    // 格式化地址（确保是 0x 开头的大写十六进制）
    String formattedAddr = address.trim();
    if (!formattedAddr.startsWith('0x') && !formattedAddr.startsWith('0X')) {
      formattedAddr = '0x$formattedAddr';
    }
    formattedAddr = formattedAddr.toUpperCase();

    // 检查是否已存在
    if (selectedTargetAddresses.contains(formattedAddr)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地址已存在')),
      );
      return;
    }

    setState(() {
      selectedTargetAddresses.add(formattedAddr);
    });
    _targetController.clear();
  }

  /// 显示目标地址选择弹窗
  void _showTargetSelectionDialog() {
    // 临时选中状态，用于弹窗内的选择
    Set<String> tempSelected = {};
    // 搜索关键词
    String searchQuery = '';

    // 按 count 排序（降序）
    final sortedTargets = List<FilterTarget>.from(availableTargets)
      ..sort((a, b) => b.count.compareTo(a.count));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            // 根据搜索关键词过滤
            final filteredTargets = searchQuery.isEmpty
                ? sortedTargets
                : sortedTargets.where((target) {
                    final query = searchQuery.toLowerCase();
                    return target.address.toLowerCase().contains(query) ||
                        target.d.toString().contains(query) ||
                        target.f.toLowerCase().contains(query) ||
                        target.count.toString().contains(query);
                  }).toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(child: Text('选择目标地址')),
                  Text(
                    '${tempSelected.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 500,
                child: Column(
                  children: [
                    // 搜索框
                    TextField(
                      decoration: InputDecoration(
                        hintText: '搜索地址、D值、F值...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setDialog(() => searchQuery = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    // 统计信息
                    Row(
                      children: [
                        Text(
                          '共 ${filteredTargets.length} 个地址',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setDialog(() {
                              if (tempSelected.length == filteredTargets.length) {
                                tempSelected.clear();
                              } else {
                                tempSelected = filteredTargets.map((t) => t.address).toSet();
                              }
                            });
                          },
                          child: Text(
                            tempSelected.length == filteredTargets.length ? '取消全选' : '全选',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 列表
                    Expanded(
                      child: filteredTargets.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  const SizedBox(height: 16),
                                  Text('无匹配结果', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredTargets.length,
                              itemBuilder: (context, index) {
                                final target = filteredTargets[index];
                                final isSelected = tempSelected.contains(target.address);

                                return CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (selected) {
                                    setDialog(() {
                                      if (selected == true) {
                                        tempSelected.add(target.address);
                                      } else {
                                        tempSelected.remove(target.address);
                                      }
                                    });
                                  },
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          target.address,
                                          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${target.count}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    'D: ${target.d} | F: ${target.f}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    // 追加选中的地址到列表（不覆盖，去重）
                    setState(() {
                      for (final addr in tempSelected) {
                        if (!selectedTargetAddresses.contains(addr)) {
                          selectedTargetAddresses.add(addr);
                        }
                      }
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基址过滤'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 过滤模式选择
            _buildModeCard(),
            const SizedBox(height: 16),

            // 过滤配置
            _buildConfigCard(),
            const SizedBox(height: 16),

            // 文件选择
            _buildFileCard(),
            const SizedBox(height: 16),

            // 目标地址选择
            _buildTargetCard(),
            const SizedBox(height: 16),

            // 操作按钮
            _buildActionButtons(),
            const SizedBox(height: 16),

            // 终端面板（所有模式的面板都保留在树中，用 Offstage 控制显示/隐藏）
            ...FilterMode.values.map((mode) {
              final isCurrentMode = mode == filterMode;
              final showTerminal = _showTerminalByMode[mode] ?? false;
              final hasTask = _taskIdByMode[mode] != null;
              final shouldShow = isCurrentMode && showTerminal && hasTask;

              return Offstage(
                offstage: !shouldShow,
                child: Column(
                  children: [
                    _buildTerminalCardForMode(mode),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            }),

            // 提示
            _buildTipCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 过滤模式卡片
  Widget _buildModeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('过滤模式', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 4),
                _buildHelpIcon('过滤模式说明', '格式过滤：从 .out/.bin 文件中选择目标地址进行过滤，可生成格式文件或文本文件。\n\n'
                    '文本过滤：从 .txt 文件中过滤有效的指针链。'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<FilterMode>(
                segments: const [
                  ButtonSegment(
                    value: FilterMode.format,
                    label: Text('格式过滤'),
                    icon: Icon(Icons.data_object),
                  ),
                  ButtonSegment(
                    value: FilterMode.text,
                    label: Text('文本过滤'),
                    icon: Icon(Icons.text_snippet),
                  ),
                ],
                selected: {filterMode},
                onSelectionChanged: (Set<FilterMode> selected) {
                  final newMode = selected.first;
                  if (newMode != filterMode) {
                    setState(() {
                      filterMode = newMode;
                    });
                    _loadFiles();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 过滤配置卡片
  Widget _buildConfigCard() {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('过滤配置', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),

          // 输出格式（仅格式过滤模式）
          if (filterMode == FilterMode.format) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const Text('输出格式'),
                  const Spacer(),
                  SizedBox(
                    width: 180,
                    child: SegmentedButton<OutputFormat>(
                      segments: const [
                        ButtonSegment(
                          value: OutputFormat.txt,
                          label: Text('文本'),
                        ),
                        ButtonSegment(
                          value: OutputFormat.bin,
                          label: Text('格式'),
                        ),
                      ],
                      selected: {outputFormat},
                      onSelectionChanged: (Set<OutputFormat> selected) {
                        setState(() => outputFormat = selected.first);
                        // 更新输出路径
                        if (selectedFile != null) {
                          _updateOutputPath();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],

          // 输出路径（只读显示）
          ListTile(
            title: const Text('输出路径'),
            subtitle: Text(
              _outputPath.isNotEmpty ? _outputPath.split('/').last : '请先选择文件',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 进程位数
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
                      setState(() {
                        is32Bit = selected.first;
                      });
                      // 更新当前模式的输出路径
                      if (selectedFile != null) {
                        _updateOutputPath();
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

  /// 文件选择卡片
  Widget _buildFileCard() {
    // 根据过滤模式确定文件类型提示
    String fileHint;
    switch (filterMode) {
      case FilterMode.format:
        fileHint = '.out/.bin';
        break;
      case FilterMode.text:
        fileHint = '.txt';
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
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: selectFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: selectedFile == null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('点击选择 $fileHint 文件', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ],
                      )
                    : Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: Text(
                              selectedFile!.extension.toUpperCase(),
                              style: const TextStyle(fontSize: 10, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedFile!.name,
                                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  '${selectedFile!.sizeText} | ${selectedFile!.modified}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() {
                                selectedFile = null;
                                selectedTargetAddresses.clear();
                                availableTargets.clear();
                              });
                            },
                          ),
                        ],
                      ),
              ),
            ),

            // 功能入口
            const Divider(),

            // 指针批量调试
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.bug_report, color: Theme.of(context).colorScheme.primary),
              title: const Text('指针批量调试'),
              subtitle: Text(
                '批量测试指针链有效性',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.push('/pointer-debug');
              },
            ),
            const Divider(),

            // 模板转换
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.content_copy, color: Theme.of(context).colorScheme.primary),
              title: const Text('模板转换'),
              subtitle: Text(
                '指针链模板格式转换',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('模板转换页面开发中...')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 目标地址选择卡片
  Widget _buildTargetCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('目标地址', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (selectedTargetAddresses.isNotEmpty)
                  Badge(
                    label: Text('${selectedTargetAddresses.length}'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // 手动输入地址
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _targetController,
                    decoration: InputDecoration(
                      hintText: '输入地址 (0x...)',
                      prefixIcon: const Icon(Icons.edit_location),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    onSubmitted: _addTargetAddress,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => _addTargetAddress(_targetController.text),
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  onPressed: selectedFile == null ? null : _loadTargets,
                  icon: _isLoadingTargets
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.list),
                  tooltip: '从文件加载地址列表',
                ),
              ],
            ),

            // 已选地址列表
            if (selectedTargetAddresses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '已选地址 (${selectedTargetAddresses.length})',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() => selectedTargetAddresses.clear());
                          },
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: selectedTargetAddresses.map((addr) {
                        return Chip(
                          label: Text(
                            addr,
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() {
                              selectedTargetAddresses.remove(addr);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
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
        onPressed: startFilter,
        icon: const Icon(Icons.play_arrow),
        label: Text(filterMode == FilterMode.format ? '开始格式过滤' : '开始文本过滤'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  /// 提示卡片
  Widget _buildTipCard() {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.tips_and_updates, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                filterMode == FilterMode.format
                    ? '格式过滤：选择 .out/.bin 文件，输入或加载目标地址后过滤'
                    : '文本过滤：选择 .txt 文件，过滤有效的指针链',
                style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 为指定模式构建终端面板卡片
  Widget _buildTerminalCardForMode(FilterMode mode) {
    // 获取或创建终端面板
    if (!_terminalPanels.containsKey(mode) || _terminalPanels[mode] == null) {
      final taskId = _taskIdByMode[mode];
      if (taskId != null) {
        _terminalPanels[mode] = TerminalPanel(
          key: ValueKey('terminal_filter_${mode}_$taskId'),
          taskId: taskId,
          onComplete: () {
            // 过滤完成后刷新文件列表
            _loadFiles();
          },
        );
      }
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
            child: _terminalPanels[mode],
          ),
        ],
      ),
    );
  }

  /// 选择文件弹窗
  Future<void> selectFile() async {
    if (!mounted) return;

    String searchText = '';
    FilterFile? tempSelected = selectedFile;
    Function(VoidCallback)? setDialogState;
    bool isLoading = true;

    // 先弹窗，显示加载中
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            setDialogState = setDialog;

            final filteredFiles = availableFiles.where((file) {
              return file.name.toLowerCase().contains(searchText.toLowerCase());
            }).toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Text('选择文件'),
                  const Spacer(),
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
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
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
                              Expanded(
                                child: RadioGroup<FilterFile>(
                                  groupValue: tempSelected,
                                  onChanged: (value) {
                                    setDialog(() => tempSelected = value);
                                  },
                                  child: ListView.builder(
                                    itemCount: filteredFiles.length,
                                    itemBuilder: (context, index) {
                                      final file = filteredFiles[index];
                                      return RadioListTile<FilterFile>(
                                        value: file,
                                        title: Text(file.name, style: const TextStyle(fontFamily: 'monospace')),
                                        subtitle: Text('${file.sizeText} | ${file.modified}'),
                                        secondary: CircleAvatar(
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
                      selectedFile = tempSelected;
                      selectedTargetAddresses.clear();
                      availableTargets.clear();
                    });
                    Navigator.pop(context);
                    // 更新输出路径
                    _updateOutputPath();
                  },
                  child: const Text('确定'),
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

      List<String> extensions;
      switch (filterMode) {
        case FilterMode.format:
          extensions = ['out', 'bin'];
          break;
        case FilterMode.text:
          extensions = ['txt'];
          break;
      }

      final files = await wsService.getFiles(_dataDir, extensions);
      if (files != null && mounted) {
        setState(() {
          availableFiles = files.map((f) => FilterFile.fromJson(f)).toList();
        });
      }
    } catch (e) {
      logger.error('FilterScreen', '加载文件失败', e);
    } finally {
      if (mounted && setDialogState != null) {
        setDialogState!(() {
          isLoading = false;
        });
      }
    }
  }

  /// 开始过滤
  Future<void> startFilter() async {
    if (selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择文件')),
      );
      return;
    }

    if (selectedTargetAddresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入或选择目标地址')),
      );
      return;
    }

    final wsService = context.read<WsService>();
    final appConfig = context.read<AppConfig>();

    // 获取当前进程 PID
    final pid = appConfig.selectedPid ?? 0;
    if (pid <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择目标进程')),
        );
      }
      return;
    }

    // 确定输入模式
    String mode;
    switch (selectedFile!.extension) {
      case 'txt':
        mode = 'text';
        break;
      default:
        mode = 'bin';
        break;
    }

    try {
      if (filterMode == FilterMode.format) {
        // 格式过滤：对每个选中的地址执行过滤
        int successCount = 0;
        int totalCount = selectedTargetAddresses.length;

        // 确定输出模式
        final outputModeStr = outputFormat == OutputFormat.txt ? 'text' : 'bin';

        // 获取输出路径
        await _updateOutputPath();
        if (_outputPath.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('无法生成输出路径')),
            );
          }
          return;
        }

        // 确定 reader 类型
        String readerType = '';
        switch (appConfig.rwMethod) {
          case 0:
            readerType = 'syscall';
            break;
          case 1:
            readerType = 'pread';
            break;
          case 2:
            readerType = appConfig.libPath;
            break;
        }

        for (final address in selectedTargetAddresses) {
          final targetAddress = int.tryParse(address.replaceAll('0x', ''), radix: 16);
          if (targetAddress == null) continue;

          final taskId = await wsService.filterRun(
            inputFile: selectedFile!.path,
            mode: mode,
            is32Bit: is32Bit,
            targetAddress: targetAddress,
            outputFile: _outputPath,
            pid: pid,
            outputMode: outputModeStr,
            reader: readerType,
          );

          if (taskId != null && mounted) {
            setState(() {
              _taskIdByMode[filterMode] = taskId;
              _showTerminalByMode[filterMode] = true;
              _terminalPanels[filterMode] = null; // 重新创建终端面板
            });
            successCount++;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('格式过滤已启动: $successCount/$totalCount 成功'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        // 文本过滤：对每个选中的地址执行过滤
        int successCount = 0;
        int totalCount = selectedTargetAddresses.length;

        // 获取输出路径
        await _updateOutputPath();
        if (_outputPath.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('无法生成输出路径')),
            );
          }
          return;
        }

        // 确定 reader 类型
        String readerType = '';
        switch (appConfig.rwMethod) {
          case 0:
            readerType = 'syscall';
            break;
          case 1:
            readerType = 'pread';
            break;
          case 2:
            readerType = appConfig.libPath;
            break;
        }

        for (final address in selectedTargetAddresses) {
          final targetAddress = int.tryParse(address.replaceAll('0x', ''), radix: 16);
          if (targetAddress == null) continue;

          final taskId = await wsService.filterRun(
            inputFile: selectedFile!.path,
            mode: mode,
            is32Bit: is32Bit,
            targetAddress: targetAddress,
            outputFile: _outputPath,
            pid: pid,
            outputMode: 'text', // 文本过滤只能输出文本
            reader: readerType,
          );

          if (taskId != null && mounted) {
            setState(() {
              _taskIdByMode[filterMode] = taskId;
              _showTerminalByMode[filterMode] = true;
              _terminalPanels[filterMode] = null; // 重新创建终端面板
            });
            successCount++;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('文本过滤已启动: $successCount/$totalCount 成功'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('过滤失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
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

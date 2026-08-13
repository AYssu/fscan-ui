import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fscan/core/config/app_config.dart';
import 'package:fscan/core/services/kami_service.dart';
import 'package:fscan/core/network/ws_service.dart';
import 'package:fscan/shared/widgets/terminal_panel.dart';

/// 格式文件页面 - MD3 风格
class FormatScreen extends StatefulWidget {
  const FormatScreen({super.key});

  @override
  State<FormatScreen> createState() => _FormatScreenState();
}

class _FormatScreenState extends State<FormatScreen> {
  // 格式数量
  int formatCount = 300000000; // 默认3亿
  String formatCountText = '3亿';

  // 预览结果
  bool enablePreview = false;

  // 架构
  bool is32Bit = false;

  // 文件夹模式
  bool folderMode = false;

  // 输出路径
  String outputPath = '';

  // 层级限制
  int? levelMin;
  int? levelMax;

  // 选中的文件（源文件 .out/.bin）
  FormatFile? selectedFile;

  // 转换后的文件路径
  String? convertedFilePath;

  // 预览结果（读取转换后的 txt 前200行）
  List<String> previewResults = [];
  bool _isPreviewLoading = false; // ignore: prefer_final_fields

  // 终端状态
  String? _currentTaskId;
  bool _showTerminal = false;

  // 文件列表
  List<FormatFile> availableFiles = [];
  bool _isLoadingFiles = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFiles();
    });
  }

  /// 加载文件列表
  Future<void> _loadFiles() async {
    if (!mounted) return;

    setState(() => _isLoadingFiles = true);

    try {
      final wsService = context.read<WsService>();
      final appConfig = context.read<AppConfig>();

      // 确定目录：如果有选中的包名，则使用扫描数据路径+包名
      String dir = appConfig.dataPath;
      if (appConfig.selectedPackageName != null) {
        dir = '$dir/${appConfig.selectedPackageName}';
      }

      final files = await wsService.getFiles(dir, ['out', 'bin']);

      if (files != null && mounted) {
        setState(() {
          availableFiles = files.map((f) => FormatFile.fromJson(f)).toList();
          _isLoadingFiles = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingFiles = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFiles = false);
      }
    }
  }

  /// 编辑格式数量
  void _editFormatCount() {
    final controller = TextEditingController(text: formatCount.toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('格式数量'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '数量',
                  border: OutlineInputBorder(),
                  suffixText: '条',
                ),
              ),
              const SizedBox(height: 16),
              // 推荐数量
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQuickCount('100万', 1000000),
                  _buildQuickCount('500万', 5000000),
                  _buildQuickCount('1亿', 100000000),
                  _buildQuickCount('3亿', 300000000),
                  _buildQuickCount('5亿', 500000000),
                  _buildQuickCount('全部', 0),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(controller.text);
                if (v != null && v >= 0) {
                  setState(() {
                    formatCount = v;
                    formatCountText = _formatCountText(v);
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  /// 快捷数量按钮
  Widget _buildQuickCount(String label, int value) {
    final isSelected = formatCount == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          formatCount = value;
          formatCountText = _formatCountText(value);
        });
        Navigator.pop(context);
      },
    );
  }

  /// 格式化数量显示
  String _formatCountText(int value) {
    if (value == 0) return '全部';
    if (value >= 100000000) return '${value ~/ 100000000}亿';
    if (value >= 10000) return '${value ~/ 10000}万';
    return value.toString();
  }

  /// 根据选中文件和文件夹模式计算输出路径
  void _updateOutputPath() {
    if (selectedFile == null) return;

    final filePath = selectedFile!.path;
    final dir = filePath.substring(0, filePath.lastIndexOf('/'));
    final fileName = filePath.substring(filePath.lastIndexOf('/') + 1);

    String outputName;
    if (folderMode) {
      // 文件夹模式：去掉后缀，作为文件夹名
      final lastDot = fileName.lastIndexOf('.');
      outputName = lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
    } else {
      // 非文件夹模式：替换后缀为 .txt
      if (fileName.endsWith('.out')) {
        outputName = fileName.replaceAll('.out', '.txt');
      } else if (fileName.endsWith('.bin')) {
        outputName = fileName.replaceAll('.bin', '.txt');
      } else {
        outputName = '$fileName.txt';
      }
    }

    setState(() => outputPath = '$dir/$outputName');
  }

  /// 编辑层级限制
  void _editLevelLimit() {
    final minController = TextEditingController(text: levelMin?.toString() ?? '');
    final maxController = TextEditingController(text: levelMax?.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('层级限制'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '最小层级',
                  border: OutlineInputBorder(),
                  hintText: '不限制',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: maxController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '最大层级',
                  border: OutlineInputBorder(),
                  hintText: '不限制',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  levelMin = int.tryParse(minController.text);
                  levelMax = int.tryParse(maxController.text);
                });
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('格式文件'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 提示卡片
            _buildTipCard(),
            const SizedBox(height: 16),

            // 配置卡片
            _buildConfigCard(),
            const SizedBox(height: 16),

            // 文件选择卡片
            _buildFileCard(),
            const SizedBox(height: 16),

            // 预览结果卡片（转换后显示）
            if (convertedFilePath != null) ...[
              _buildPreviewCard(),
              const SizedBox(height: 16),
            ],

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
    );
  }

  /// 提示卡片
  Widget _buildTipCard() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '使用提示',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• 指针链条结果数量太多时，不建议直接转换\n'
                    '• 垃圾指针链条占比约99%，推荐先对比筛选\n'
                    '• 本功能适合有能力自行查看或筛选的用户',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 配置卡片
  Widget _buildConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('转换配置', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),

            // 格式数量
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('格式数量'),
              subtitle: const Text('限制转换的指针链条数量'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatCountText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: _editFormatCount,
                  ),
                ],
              ),
            ),
            const Divider(),

            // 架构选择
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Text('架构'),
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
            const Divider(),

            // 文件夹模式
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('文件夹输出'),
              subtitle: const Text('输出为文件夹格式'),
              value: folderMode,
              onChanged: (v) {
                setState(() => folderMode = v);
                // 切换时自动更新输出路径
                _updateOutputPath();
              },
            ),
            const Divider(),

            // 输出路径
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('输出路径'),
              subtitle: Text(
                outputPath.isEmpty ? '选择文件后自动生成' : outputPath.split('/').last,
                style: TextStyle(
                  color: outputPath.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.primary,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: _updateOutputPath,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重新生成'),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
            ),
            const Divider(),

            // 层级限制
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('层级限制'),
              subtitle: Text(
                levelMin != null || levelMax != null
                    ? '最小: ${levelMin ?? "无"}  最大: ${levelMax ?? "无"}'
                    : '不限制',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editLevelLimit,
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
            Row(
              children: [
                Icon(Icons.folder_open, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('选择文件', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (_isLoadingFiles)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _openFileSelector,
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
                          Text('点击选择 .out 或 .bin 文件', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
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
                                  '${selectedFile!.arch ?? "未知"} | ${selectedFile!.sizeText} | ${selectedFile!.modified}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() {
                              selectedFile = null;
                              convertedFilePath = null;
                              previewResults = [];
                            }),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 预览结果卡片（显示转换后的 txt 前200行）
  Widget _buildPreviewCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('预览结果', style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        convertedFilePath!.split('/').last,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isPreviewLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (previewResults.isNotEmpty)
                  Badge(
                    label: Text('${previewResults.length}'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 300,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isPreviewLoading
                  ? const Center(child: CircularProgressIndicator())
                  : previewResults.isEmpty
                      ? Center(
                          child: Text(
                            '暂无预览数据',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          itemCount: previewResults.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                previewResults[index],
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
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
        onPressed: selectedFile == null ? null : _startConvert,
        icon: const Icon(Icons.transform),
        label: const Text('开始转换'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
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

  /// 打开文件选择弹窗
  Future<void> _openFileSelector() async {
    await _loadFiles();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            return AlertDialog(
              title: Row(
                children: [
                  const Text('选择文件'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      await _loadFiles();
                      setDialog(() {});
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: _isLoadingFiles
                    ? const Center(child: CircularProgressIndicator())
                    : availableFiles.isEmpty
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
                        : ListView.builder(
                            itemCount: availableFiles.length,
                            itemBuilder: (context, index) {
                              final file = availableFiles[index];
                              final isSelected = selectedFile?.path == file.path;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  child: Text(
                                    file.extension.toUpperCase(),
                                    style: const TextStyle(fontSize: 10, color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  file.name,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                ),
                                subtitle: Text('${file.arch ?? "未知"} | ${file.sizeText} | ${file.modified}'),
                                trailing: isSelected
                                    ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                                    : null,
                                onTap: () {
                                  Navigator.pop(context);
                                  setState(() {
                                    selectedFile = file;
                                    convertedFilePath = null;
                                    previewResults = [];
                                  });
                                  // 根据文件名计算输出路径
                                  _updateOutputPath();
                                },
                              );
                            },
                          ),
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
      },
    );
  }

  /// 开始转换
  Future<void> _startConvert() async {
    if (!mounted) return;

    final wsService = context.read<WsService>();
    final kamiService = context.read<KamiService>();

    // 启动格式转换
    final taskId = await wsService.convertFormatFile(
      filePath: selectedFile!.path,
      limit: formatCount,
      is32Bit: is32Bit,
      folder: folderMode,
      levelMin: levelMin,
      levelMax: levelMax,
      outputPath: outputPath.isNotEmpty ? outputPath : null,
      kamiKey: kamiService.kamiKey,
    );

    if (taskId != null && mounted) {
      setState(() {
        _currentTaskId = taskId;
        _showTerminal = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('格式转换已启动'),
          duration: Duration(seconds: 1),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('启动格式转换失败')),
      );
    }
  }
}

/// 文件数据模型
class FormatFile {
  final String name;
  final String path;
  final int size;
  final String modified;
  final String extension;
  final String? arch;

  FormatFile({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    required this.extension,
    this.arch,
  });

  factory FormatFile.fromJson(Map<String, dynamic> json) {
    return FormatFile(
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

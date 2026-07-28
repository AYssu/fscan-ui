import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fscan/core/network/ws_service.dart';

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

  // 选中的文件（源文件 .out/.bin）
  FormatFile? selectedFile;

  // 转换后的文件路径
  String? convertedFilePath;

  // 预览结果（读取转换后的 txt 前200行）
  List<String> previewResults = [];
  bool _isPreviewLoading = false;

  // 转换状态
  bool _isConverting = false;

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
      final files = await wsService.getFiles('/sdcard/fscan/data', ['out', 'bin']);

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

  /// 预览转换后的 txt 文件（前200行）
  Future<void> _previewConvertedFile() async {
    if (convertedFilePath == null) return;

    setState(() => _isPreviewLoading = true);

    try {
      final wsService = context.read<WsService>();
      final results = await wsService.previewConvertedFile(convertedFilePath!);

      if (results != null && mounted) {
        setState(() {
          previewResults = results;
          _isPreviewLoading = false;
        });
      } else if (mounted) {
        setState(() {
          previewResults = [];
          _isPreviewLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          previewResults = [];
          _isPreviewLoading = false;
        });
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
        onPressed: selectedFile == null || _isConverting ? null : _startConvert,
        icon: _isConverting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.transform),
        label: Text(_isConverting ? '转换中...' : '开始转换'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
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
                                  setState(() => selectedFile = file);
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
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认转换'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('文件: ${selectedFile!.name}'),
              Text('数量限制: $formatCountText'),
              Text('架构: ${is32Bit ? "32位" : "64位"}'),
              const SizedBox(height: 16),
              const Text(
                '注意：转换过程可能需要较长时间，请勿关闭应用。',
                style: TextStyle(color: Colors.orange),
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
              child: const Text('确定转换'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    // 开始转换
    setState(() {
      _isConverting = true;
      previewResults = [];
    });

    try {
      final wsService = context.read<WsService>();
      final result = await wsService.convertFormatFile(
        selectedFile!.path,
        formatCount,
        is32Bit,
      );

      if (result != null && mounted) {
        // 转换成功，保存生成的 txt 文件路径
        setState(() {
          convertedFilePath = result;
          _isConverting = false;
        });

        // 自动预览转换后的文件
        if (enablePreview) {
          await _previewConvertedFile();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('转换完成: ${result.split('/').last}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (mounted) {
        setState(() => _isConverting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('转换失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConverting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('转换失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

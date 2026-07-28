import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:fscan/core/network/ws_service.dart';

/// 文件数据模型
class FilterFile {
  final String name;
  final String path;
  final int size;
  final String modified;
  final String extension;
  final String? arch;  // out/bin 文件才有 arch

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
}

/// 基址过滤页面 - MD3 风格
class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  String violentInitMaxDb = '无限制';
  bool tempInit = true;
  bool is32Bit = false;
  FilterFile? selectedFile;
  String outputPath = '/storage/emulated/0/fscan/a1.txt';

  // 文件相关
  String dataDir = '/sdcard/fscan/data';
  List<FilterFile> availableFiles = [];
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
      final files = await wsService.getFiles(dataDir, ['txt']);

      if (files != null && mounted) {
        setState(() {
          availableFiles = files.map((f) => FilterFile.fromJson(f)).toList();
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
            // 过滤配置
            _buildConfigCard(),
            const SizedBox(height: 16),

            // 文件选择
            _buildFileCard(),
            const SizedBox(height: 16),

            // 操作按钮
            _buildActionButtons(),
            const SizedBox(height: 16),

            // 提示
            _buildTipCard(),
            const SizedBox(height: 32),
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
          // 过滤数量
          ListTile(
            title: const Text('过滤数量'),
            trailing: Text(_formatFilterCount(violentInitMaxDb), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editFilterCount,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          // 缓存优化
          SwitchListTile(
            title: Row(
              children: [
                const Text('缓存优化'),
                const SizedBox(width: 4),
                _buildHelpIcon('缓存优化说明', '缓存指的是先获取指针数据，再进行指针跳转。\n\n'
                    '优点：速度快，获取指针后理论上游戏可以退出，因为指针数据已经到本地了。\n\n'
                    '缺点：会漏一丝丝指针。\n\n'
                    '关闭后：每个指针都进行指针数据读取和跳转，游戏需要在后台持续运行。'),
              ],
            ),
            subtitle: Text(tempInit ? '开启' : '关闭'),
            value: tempInit,
            onChanged: (v) => setState(() => tempInit = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          // 输出路径
          ListTile(
            title: const Text('输出路径'),
            trailing: Text(
              outputPath.split('/').last,
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12),
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
                        selectedFile = null; // 清空选择的文件
                      });
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
                          Text('点击选择 .txt 文件', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
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
                            onPressed: () => setState(() => selectedFile = null),
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
                // TODO: 跳转到模板转换页面
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

  /// 操作按钮
  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: startFilter,
        icon: const Icon(Icons.play_arrow),
        label: const Text('开始过滤'),
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
                '先格式文件对比生成 .txt 后再进行过滤',
                style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑过滤数量
  void editFilterCount() {
    final controller = TextEditingController(
      text: violentInitMaxDb == '无限制' ? '' : violentInitMaxDb,
    );
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('过滤数量'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  ].map((item) {
                    final isSelected = violentInitMaxDb == item['value'];
                    return ChoiceChip(
                      labelStyle: const TextStyle(fontSize: 12),
                      label: Text(item['label']!),
                      selected: isSelected,
                      onSelected: (_) {
                        setDialog(() {
                          violentInitMaxDb = item['value']!;
                          controller.text = item['value'] == '无限制' ? '' : item['value']!;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
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
                  setState(() => violentInitMaxDb = (value.isEmpty || value == '0') ? '无限制' : value);
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
  Future<void> selectFile() async {
    // 先加载文件
    await _loadFiles();

    if (!mounted) return;

    String searchText = '';
    FilterFile? tempSelected = selectedFile;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            final filteredFiles = availableFiles.where((file) {
              return file.name.toLowerCase().contains(searchText.toLowerCase());
            }).toList();

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
                height: 350,
                child: _isLoadingFiles
                    ? const Center(child: CircularProgressIndicator())
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
                    setState(() => selectedFile = tempSelected);
                    Navigator.pop(context);
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 格式化过滤数量显示
  String _formatFilterCount(String count) {
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

  /// 开始过滤
  void startFilter() {
    if (selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择文件')),
      );
      return;
    }
    // TODO: 实现过滤逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('开始过滤...')),
    );
  }
}

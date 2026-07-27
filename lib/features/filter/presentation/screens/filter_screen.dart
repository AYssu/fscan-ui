import 'dart:async';
import 'package:flutter/material.dart';

/// 文件数据模型
class FilterFile {
  final String name;
  final String arch;
  final String size;
  final String date;

  FilterFile({
    required this.name,
    required this.arch,
    required this.size,
    required this.date,
  });
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

  // 模拟文件数据（txt文件）
  final List<FilterFile> allFiles = [
    FilterFile(name: 'a1.txt', arch: 'x64', size: '10.01mb', date: '2026-12-12 13:12:12'),
    FilterFile(name: 'a2.txt', arch: 'x64', size: '8.5mb', date: '2026-12-12 14:20:00'),
    FilterFile(name: 'b1.txt', arch: 'arm64', size: '12.3mb', date: '2026-12-13 10:00:00'),
    FilterFile(name: 'c1.txt', arch: 'x86', size: '5.5mb', date: '2026-12-14 09:00:00'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基址过滤'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: resetConfig),
        ],
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
                              selectedFile!.arch == 'x64' ? '64' : selectedFile!.arch == 'x86' ? '32' : 'A',
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
                                  '${selectedFile!.arch} | ${selectedFile!.size}',
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
  void selectFile() {
    // 根据位数筛选文件
    final filteredByArch = allFiles.where((file) {
      if (is32Bit) {
        return file.arch == 'x86';
      } else {
        return file.arch == 'x64' || file.arch == 'arm64';
      }
    }).toList();

    String searchText = '';
    FilterFile? tempSelected = selectedFile;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            final filteredFiles = filteredByArch.where((file) {
              return file.name.toLowerCase().contains(searchText.toLowerCase());
            }).toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Text('选择文件'),
                  const Spacer(),
                  Text(
                    is32Bit ? '32位' : '64位',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: Column(
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
                      child: filteredFiles.isEmpty
                          ? Center(
                              child: Text(
                                '没有找到${is32Bit ? '32位' : '64位'}文件',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredFiles.length,
                              itemBuilder: (context, index) {
                                final file = filteredFiles[index];
                                final isSelected = tempSelected == file;
                                return RadioListTile<FilterFile>(
                                  value: file,
                                  groupValue: tempSelected,
                                  onChanged: (value) {
                                    setDialog(() => tempSelected = value);
                                  },
                                  title: Text(file.name, style: const TextStyle(fontFamily: 'monospace')),
                                  subtitle: Text('${file.arch} | ${file.size} | ${file.date}'),
                                  secondary: CircleAvatar(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    radius: 12,
                                    child: Text(
                                      file.arch == 'x64' ? '64' : file.arch == 'x86' ? '32' : 'A',
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

  /// 重置配置
  void resetConfig() {
    setState(() {
      violentInitMaxDb = '无限制';
      tempInit = true;
      is32Bit = false;
      selectedFile = null;
    });
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

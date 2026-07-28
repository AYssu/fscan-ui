import 'package:flutter/material.dart';

/// 对比模式枚举
enum CompareMode {
  basic,    // 基础对比
  fast,     // 极速对比
  single,   // 单线程对比
}

/// 文件数据模型
class CompareFile {
  final String name;
  final String arch;
  final String size;
  final String date;

  CompareFile({
    required this.name,
    required this.arch,
    required this.size,
    required this.date,
  });
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
  List<CompareFile> selectedFiles = [];
  bool is32Bit = false; // 进程位数
  String outputPath = '/storage/emulated/0/fscan/a1.txt';

  // 模拟文件数据
  final List<CompareFile> allFiles = [
    CompareFile(name: 'a1.out', arch: 'x64', size: '10.01mb', date: '2026-12-12 13:12:12'),
    CompareFile(name: 'a2.out', arch: 'x64', size: '8.5mb', date: '2026-12-12 14:20:00'),
    CompareFile(name: 'b1.out', arch: 'arm64', size: '12.3mb', date: '2026-12-13 10:00:00'),
    CompareFile(name: 'b2.out', arch: 'arm64', size: '9.8mb', date: '2026-12-13 11:30:00'),
    CompareFile(name: 'c1.out', arch: 'x64', size: '15.2mb', date: '2026-12-14 09:00:00'),
    CompareFile(name: 'c2.out', arch: 'x86', size: '5.5mb', date: '2026-12-14 15:00:00'),
  ];

  // 当前模式支持的最大文件数
  int get maxFileCount {
    switch (compareMode) {
      case CompareMode.basic:
        return 2;
      case CompareMode.fast:
      case CompareMode.single:
        return 8;
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
                _buildHelpIcon('对比模式说明', '基础对比：功能最多，但是速度会慢一些，因为加了很多条件的判断。\n\n'
                    '极速对比：最快，但是舍弃了到指针地址级别的判断，对比速度快一些。\n\n'
                    '单线程：因为按照模块进行多线程分配，默认单线程是大核，如果多线程但只有一个线程触发，有可能分配到小核，也会触发合并操作，速度反而慢。如果量少，单线程比多线程快。'),
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
                    value: CompareMode.single,
                    label: Text('单线程'),
                  ),
                ],
                selected: {compareMode},
                onSelectionChanged: (Set<CompareMode> selected) {
                  setState(() {
                    compareMode = selected.first;
                    // 切换模式时清理超出限制的文件
                    if (selectedFiles.length > maxFileCount) {
                      selectedFiles = selectedFiles.sublist(0, maxFileCount);
                    }
                  });
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
    final isBasic = compareMode == CompareMode.basic;
    final isFast = compareMode == CompareMode.fast;
    final isSingle = compareMode == CompareMode.single;

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

          // 限制数量 - 所有模式都有
          ListTile(
            title: const Text('限制数量'),
            trailing: Text(_formatMaxDbNum(maxDbNum), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editMaxDbNum,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 线程数量 - 基础对比和极速对比
          if (!isSingle) ...[
            ListTile(
              title: const Text('线程数量'),
              trailing: Text('$threadNum 核', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              onTap: editThreadNum,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],

          // 匹配优化 - 仅极速对比
          if (isFast) ...[
            SwitchListTile(
              title: Row(
                children: [
                  const Text('匹配优化'),
                  const SizedBox(width: 4),
                  _buildHelpIcon('匹配优化说明', '如果匹配到数据则放弃后续的匹配，优先跳出循环寻找下一个节点的数据。\n\n'
                      '默认开启。\n\n'
                      '如果对数据量要求全的可以关闭，但是速度会慢一些。'),
                ],
              ),
              subtitle: Text(matchOptimize ? '开启' : '关闭'),
              value: matchOptimize,
              onChanged: (v) => setState(() => matchOptimize = v),
            ),
          ],

          // 去除层级 - 仅基础对比
          if (isBasic) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              title: Row(
                children: [
                  const Text('去除层级'),
                  const SizedBox(width: 4),
                  _buildHelpIcon('去除层级说明', '例如：libUE4.so[Cd][1]+0xfff+0x111+0x222+0x333\n\n'
                      '选中第2层，则是 0x222 这层不参与对比。\n\n'
                      '主要用于数组，或者隔层某层变化的情况。\n\n'
                      '由于倒数层级跟随层级变化，推荐配合层级限制到某一层使用。'),
                ],
              ),
              trailing: Text(
                nopLevel == 0 ? '暂无' : '第$nopLevel层',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              onTap: editNopLevel,
            ),
          ],

          // 下标判断 - 仅基础对比
          if (isBasic) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              title: Row(
                children: [
                  const Text('下标判断'),
                  const SizedBox(width: 4),
                  _buildHelpIcon('下标判断说明', '下标指的是 libUE4.so[Cd][1]、libUE4.so[Cd][2]、libUE4.so[Cd][3] 这种。\n\n'
                      '因为内存段不一样，下标(index)不一样。\n\n'
                      '主要是针对游戏混淆，第一次在1，第二次在2的这种情况。\n\n'
                      '可以使用"去除层级"进行优化，但是理论上大部分游戏均需要单独索引对比，非必要勿关闭。'),
                ],
              ),
              subtitle: Text(indexCheck ? '开启' : '关闭'),
              value: indexCheck,
              onChanged: (v) => setState(() => indexCheck = v),
            ),
          ],

          // 输出路径
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('输出路径'),
            trailing: Text(
              outputPath.split('/').last,
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12),
            ),
          ),

          // 进程位数 - 所有模式都有
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
                        // 切换位数时清理不匹配的文件
                        selectedFiles.removeWhere((file) {
                          if (is32Bit) {
                            return file.arch != 'x86';
                          } else {
                            return file.arch == 'x86';
                          }
                        });
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
                          Text('点击选择 .out 文件', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
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
                                        '${file.arch} | ${file.size}',
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
                                    setState(() => selectedFiles.remove(file));
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
  void selectFiles() {
    List<CompareFile> tempSelected = List.from(selectedFiles);
    String searchText = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            // 根据位数筛选文件
            final filesByArch = allFiles.where((file) {
              if (is32Bit) {
                return file.arch == 'x86';
              } else {
                return file.arch == 'x64' || file.arch == 'arm64';
              }
            }).toList();

            // 搜索筛选
            final filteredFiles = filesByArch.where((file) {
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
                  const SizedBox(width: 8),
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
                child: Column(
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
                          final isSelected = tempSelected.contains(file);
                          final canSelect = tempSelected.length < maxFileCount || isSelected;

                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: canSelect
                                ? (selected) {
                                    setDialog(() {
                                      if (selected == true) {
                                        tempSelected.add(file);
                                      } else {
                                        tempSelected.remove(file);
                                      }
                                    });
                                  }
                                : null,
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
                    setState(() => selectedFiles = tempSelected);
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

  /// 开始对比
  void startCompare() {
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

    // TODO: 实现对比逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('开始${compareMode == CompareMode.basic ? "基础" : compareMode == CompareMode.fast ? "极速" : "单线程"}对比...')),
    );
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

import 'dart:async';
import 'package:flutter/material.dart';

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
  List<ModuleItem> selectedModules = []; // 存储完整模块信息
  bool handlePageFault = false;
  bool is32Bit = false;
  bool byteAlignment = false;
  bool pageAlignment = false;
  int scanCores = 8;
  bool moduleExtension = false;
  bool negativeOffset = false;

  // 模拟接口数据
  final List<ModuleItem> allModules = [
    ModuleItem(name: 'libil2cpp.so', index: '1', type: 'Cd', startAddress: '0x1000', endAddress: '0x2000'),
    ModuleItem(name: 'libil2cpp.so', index: '2', type: 'Cb', startAddress: '0x3000', endAddress: '0x4000'),
    ModuleItem(name: 'libil2cpp.so', index: '3', type: 'Xa', startAddress: '0x5000', endAddress: '0x6000'),
    ModuleItem(name: 'libunity.so', index: '1', type: 'Cd', startAddress: '0x7000', endAddress: '0x8000'),
    ModuleItem(name: 'libunity.so', index: '2', type: 'Cb', startAddress: '0x9000', endAddress: '0xA000'),
    ModuleItem(name: 'libnative.so', index: '1', type: 'Xa', startAddress: '0xB000', endAddress: '0xC000'),
    ModuleItem(name: 'libc.so', index: '1', type: 'Cd', startAddress: '0xD000', endAddress: '0xE000'),
    ModuleItem(name: 'libc.so', index: '2', type: 'Cb', startAddress: '0xF000', endAddress: '0x10000'),
    ModuleItem(name: 'libm.so', index: '1', type: 'Cb', startAddress: '0x11000', endAddress: '0x12000'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基址搜索'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: resetConfig,
          ),
        ],
      ),
      body: SingleChildScrollView(
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

            // 高级选项
            _buildAdvancedCard(),
            const SizedBox(height: 24),

            // 操作按钮
            _buildActionButtons(),
            const SizedBox(height: 32),
          ],
        ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                const Text('进程位数'),
                const Spacer(),
                SegmentedButton<bool>(
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
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                              setState(() {
                                selectedModules.removeWhere((m) => m.name == entry.key);
                              });
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

  /// 高级选项卡片
  Widget _buildAdvancedCard() {
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
        title: Text('高级选项', style: Theme.of(context).textTheme.titleMedium),
        children: [
          SwitchListTile(
            title: const Text('处理B4'),
            subtitle: Text(handlePageFault ? '开启' : '关闭'),
            value: handlePageFault,
            onChanged: (v) => setState(() => handlePageFault = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('字节对齐'),
            subtitle: Text(byteAlignment ? '开启' : '关闭'),
            value: byteAlignment,
            onChanged: (v) => setState(() => byteAlignment = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('分页对齐'),
            subtitle: Text(pageAlignment ? '开启' : '关闭'),
            value: pageAlignment,
            onChanged: (v) => setState(() => pageAlignment = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('扫描核心'),
            trailing: Text('$scanCores 核', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editCores,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('模块扩展'),
            subtitle: Text(moduleExtension ? '开启' : '关闭'),
            value: moduleExtension,
            onChanged: (v) => setState(() => moduleExtension = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('负偏移'),
            subtitle: Text(negativeOffset ? '开启' : '关闭'),
            value: negativeOffset,
            onChanged: (v) => setState(() => negativeOffset = v),
          ),
        ],
      ),
    );
  }

  /// 操作按钮
  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: startBasicScan,
            icon: const Icon(Icons.search),
            label: const Text('基础扫描'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: startViolentScan,
            icon: const Icon(Icons.flash_on),
            label: const Text('暴力扫描'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
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
                    const SizedBox(height: 8),
                    Text(
                      '最大值: 0x$maxValue',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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

                          // 验证地址范围
                          final addrValue = int.parse(addr, radix: 16);
                          final maxValueInt = int.parse(maxValue, radix: 16);
                          if (addrValue > maxValueInt) {
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

  void openModuleSelector() {
    // 临时选中列表
    List<ModuleItem> tempSelected = List<ModuleItem>.from(selectedModules ?? []);
    String searchText = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            // 筛选模块
            final filteredModules = allModules.where((module) {
              return module.name.toLowerCase().contains(searchText.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('选择扫描模块'),
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
                    // 模块列表
                    Expanded(
                      child: ListView.builder(
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
                    setState(() => selectedModules = tempSelected);
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

  void resetConfig() {
    setState(() {
      searchAddresses.clear();
      scanLevel = 6;
      scanRange = '0x7D0';
      selectedModules.clear();
      handlePageFault = false;
      is32Bit = false;
      byteAlignment = false;
      pageAlignment = false;
      scanCores = 8;
      moduleExtension = false;
      negativeOffset = false;
    });
  }

  void startBasicScan() {
    if (searchAddresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置目标地址')),
      );
      return;
    }
  }

  void startViolentScan() {
    if (searchAddresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置目标地址')),
      );
      return;
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

/// 模块数据模型
class ModuleItem {
  final String name;
  final String index;
  final String type;
  final String startAddress;
  final String endAddress;

  ModuleItem({
    required this.name,
    required this.index,
    required this.type,
    required this.startAddress,
    required this.endAddress,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModuleItem &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          index == other.index &&
          type == other.type &&
          startAddress == other.startAddress &&
          endAddress == other.endAddress;

  @override
  int get hashCode => name.hashCode ^ index.hashCode ^ type.hashCode ^ startAddress.hashCode ^ endAddress.hashCode;
}

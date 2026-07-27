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
  List<String> selectedModules = [];
  bool handlePageFault = false;
  String scanLimit = '无限制';
  bool is32Bit = false;
  bool byteAlignment = false;
  bool pageAlignment = false;
  int scanCores = 8;
  bool moduleExtension = false;
  bool negativeOffset = false;

  final List<Map<String, String>> moduleList = [
    {'name': 'libil2cpp.so', 'type': 'Cd'},
    {'name': 'libunity.so', 'type': 'Cb'},
    {'name': 'libnative.so', 'type': 'Xa'},
    {'name': 'libc.so', 'type': 'Cd'},
    {'name': 'libm.so', 'type': 'Cb'},
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
            trailing: Text(scanRange, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editRange,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('扫描限制'),
            trailing: Text(scanLimit, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editLimit,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('进程位数'),
            subtitle: Text(is32Bit ? '32位' : '64位'),
            value: is32Bit,
            onChanged: (v) => setState(() => is32Bit = v),
          ),
        ],
      ),
    );
  }

  /// 模块选择卡片
  Widget _buildModuleCard() {
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

            // 模块芯片
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: moduleList.map((module) {
                final name = module['name']!;
                final type = module['type']!;
                final isSelected = selectedModules.contains(name);
                return FilterChip(
                  label: Text(name),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        selectedModules.add(name);
                      } else {
                        selectedModules.remove(name);
                      }
                    });
                  },
                  avatar: CircleAvatar(
                    backgroundColor: _getTypeColor(type),
                    radius: 8,
                    child: Text(
                      type,
                      style: const TextStyle(color: Colors.white, fontSize: 8),
                    ),
                  ),
                );
              }).toList(),
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

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            return AlertDialog(
              title: const Text('目标地址'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 地址列表
                      if (tempList.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${tempList.length} 个地址'),
                            TextButton(
                              onPressed: () => setDialog(() => tempList.clear()),
                              child: const Text('清空'),
                            ),
                          ],
                        ),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 150),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: tempList.length,
                            itemBuilder: (context, index) {
                              return ListTile(
                                title: Text(tempList[index], style: const TextStyle(fontFamily: 'monospace')),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setDialog(() => tempList.removeAt(index)),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 输入框
                      TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: '地址',
                          hintText: '0x12345678',
                          prefixText: '0x ',
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 添加按钮
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            final addr = controller.text.trim();
                            if (addr.isNotEmpty) {
                              setDialog(() {
                                tempList.add('0x$addr');
                                controller.clear();
                              });
                            }
                          },
                          child: const Text('添加'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() => searchAddresses = tempList);
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

  void editLevel() {
    showDialog(
      context: context,
      builder: (context) {
        double temp = scanLevel.toDouble();
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('扫描层级'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${temp.toInt()} 层', style: Theme.of(context).textTheme.displaySmall),
                Slider(
                  value: temp,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '${temp.toInt()}',
                  onChanged: (v) => setDialog(() => temp = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  setState(() => scanLevel = temp.toInt());
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
    final controller = TextEditingController(text: scanRange);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫描范围'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '范围',
            hintText: '0x7D0',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() => scanRange = controller.text);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void editLimit() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫描限制'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '限制数量',
            hintText: '0 = 无限制',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() {
                scanLimit = controller.text.isNotEmpty && controller.text != '0'
                    ? controller.text
                    : '无限制';
              });
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void editCores() {
    showDialog(
      context: context,
      builder: (context) {
        double temp = scanCores.toDouble();
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('扫描核心'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${temp.toInt()} 核', style: Theme.of(context).textTheme.displaySmall),
                Slider(
                  value: temp,
                  min: 1,
                  max: 16,
                  divisions: 15,
                  label: '${temp.toInt()}',
                  onChanged: (v) => setDialog(() => temp = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  setState(() => scanCores = temp.toInt());
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
      scanLimit = '无限制';
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
}

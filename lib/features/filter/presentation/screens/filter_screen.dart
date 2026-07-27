import 'package:flutter/material.dart';

/// 基址过滤页面 - MD3 风格
class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  bool violentInit = false;
  int violentInitMaxDb = 0;
  int initLevel = 0;
  bool tempInit = true;
  bool is32Bit = false;
  String selectedFile = '';

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
            _buildActionCard(),
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
          SwitchListTile(
            title: const Text('载入方式'),
            subtitle: Text(violentInit ? '暴力载入' : '普通载入'),
            value: violentInit,
            onChanged: (v) => setState(() => violentInit = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('过滤数量'),
            subtitle: Text(violentInitMaxDb == 0 ? '无限制' : '$violentInitMaxDb'),
            onTap: editMaxDb,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('过滤层数'),
            subtitle: Text(initLevel == 0 ? '无限制' : '$initLevel 层'),
            onTap: editInitLevel,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('缓存载入'),
            subtitle: Text(tempInit ? '缓存' : '不缓存'),
            value: tempInit,
            onChanged: (v) => setState(() => tempInit = v),
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
                Text('选择文件', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: selectFile,
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
                        selectedFile.isEmpty
                            ? '点击选择 .out 或 .txt 文件'
                            : selectedFile,
                        style: TextStyle(
                          color: selectedFile.isEmpty
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                    ),
                    Icon(Icons.folder_open, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 操作按钮卡片
  Widget _buildActionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('过滤操作', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: startBinFilter,
                    icon: const Icon(Icons.description),
                    label: const Text('格式过滤'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: startTextFilter,
                    icon: const Icon(Icons.text_snippet),
                    label: const Text('文本过滤'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: startPointerDebug,
                icon: const Icon(Icons.bug_report),
                label: const Text('基址调试'),
              ),
            ),
          ],
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
                '格式过滤处理 .out 文件，文本过滤处理 .txt/.db 文件',
                style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void editMaxDb() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('过滤数量'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '数量',
            hintText: '0 = 无限制',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() => violentInitMaxDb = int.tryParse(controller.text) ?? 0);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void editInitLevel() {
    showDialog(
      context: context,
      builder: (context) {
        double temp = initLevel.toDouble();
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('过滤层数'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(initLevel == 0 ? '无限制' : '$initLevel 层',
                    style: Theme.of(context).textTheme.displaySmall),
                Slider(
                  value: temp,
                  min: 0,
                  max: 20,
                  divisions: 20,
                  label: '$initLevel',
                  onChanged: (v) => setDialog(() => temp = v),
                ),
                Text('0=无限制', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  setState(() => initLevel = temp.toInt());
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

  void selectFile() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件选择功能开发中...')));
  }

  void resetConfig() {
    setState(() {
      violentInit = false;
      violentInitMaxDb = 0;
      initLevel = 0;
      tempInit = true;
      is32Bit = false;
      selectedFile = '';
    });
  }

  void startBinFilter() {
    if (selectedFile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择文件')));
      return;
    }
  }

  void startTextFilter() {
    if (selectedFile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择文件')));
      return;
    }
  }

  void startPointerDebug() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('基址调试'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('输入文本基址链，如：\nlibunity.so[1][Cd]+0x25F78-0x50+0x245',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '基址链',
                hintText: 'libunity.so[1][Cd]+0x25F78',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('调试')),
        ],
      ),
    );
  }
}

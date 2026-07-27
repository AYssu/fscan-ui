import 'package:flutter/material.dart';

/// 基址对比页面 - MD3 风格
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  String levelLimit = '无限制';
  String maxDbNum = '无限制';
  int threadNum = 8;
  bool indexCheck = true;
  int nopLevel = 0;
  List<String> selectedFiles = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基址对比'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: resetConfig),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 对比配置
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

  /// 对比配置卡片
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
                Text('对比配置', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          ListTile(
            title: const Text('层级限制'),
            subtitle: Text(levelLimit),
            onTap: editLevelLimit,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('限制数量'),
            subtitle: Text(maxDbNum),
            onTap: editMaxDbNum,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('线程数量'),
            trailing: Text('$threadNum 核', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editThreadNum,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('下标判断'),
            subtitle: Text(indexCheck ? '开启' : '取消'),
            value: indexCheck,
            onChanged: (v) => setState(() => indexCheck = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('去除层级'),
            subtitle: Text(nopLevel == 0 ? '暂无' : '倒数第$nopLevel级'),
            onTap: editNopLevel,
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
                    label: Text('${selectedFiles.length}'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // 文件选择区域
            InkWell(
              onTap: selectFiles,
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
                        selectedFiles.isEmpty
                            ? '点击选择 .out 文件'
                            : selectedFiles.join(', '),
                        style: TextStyle(
                          color: selectedFiles.isEmpty
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                Icon(Icons.compare_arrows, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('对比操作', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            // 按钮网格
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.5,
              children: [
                FilledButton.icon(
                  onPressed: startNormalCompare,
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('普通对比'),
                ),
                FilledButton.tonalIcon(
                  onPressed: startFastCompare,
                  icon: const Icon(Icons.flash_on),
                  label: const Text('极速对比'),
                ),
                OutlinedButton.icon(
                  onPressed: startFullCompare,
                  icon: const Icon(Icons.select_all),
                  label: const Text('全量对比'),
                ),
                OutlinedButton.icon(
                  onPressed: startSingleThreadCompare,
                  icon: const Icon(Icons.view_column),
                  label: const Text('单线程'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: formatToText,
                icon: const Icon(Icons.text_snippet),
                label: const Text('格式转文本'),
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
                '极速对比可能丢失部分链条，推荐全量对比',
                style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void editLevelLimit() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('层级限制'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '层级',
            hintText: '6 或 3-7，0=无限制',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() => levelLimit = controller.text.isNotEmpty ? controller.text : '无限制');
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void editMaxDbNum() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('限制数量'),
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
              setState(() => maxDbNum = controller.text.isNotEmpty && controller.text != '0' ? controller.text : '无限制');
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void editThreadNum() {
    showDialog(
      context: context,
      builder: (context) {
        double temp = threadNum.toDouble();
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('线程数量'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$threadNum 核', style: Theme.of(context).textTheme.displaySmall),
                Slider(
                  value: temp,
                  min: 1,
                  max: 16,
                  divisions: 15,
                  label: '$threadNum',
                  onChanged: (v) => setDialog(() => temp = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  setState(() => threadNum = temp.toInt());
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

  void editNopLevel() {
    showDialog(
      context: context,
      builder: (context) {
        double temp = nopLevel.toDouble();
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('去除层级'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nopLevel == 0 ? '暂无' : '倒数第$nopLevel级',
                    style: Theme.of(context).textTheme.displaySmall),
                Slider(
                  value: temp,
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '$nopLevel',
                  onChanged: (v) => setDialog(() => temp = v),
                ),
                Text('0=不去除', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  setState(() => nopLevel = temp.toInt());
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

  void selectFiles() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件选择功能开发中...')));
  }

  void resetConfig() {
    setState(() {
      levelLimit = '无限制';
      maxDbNum = '无限制';
      threadNum = 8;
      indexCheck = true;
      nopLevel = 0;
      selectedFiles.clear();
    });
  }

  void startNormalCompare() {
    if (selectedFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择2个文件')));
      return;
    }
  }

  void startFastCompare() {
    if (selectedFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择2~8个文件')));
      return;
    }
  }

  void startFullCompare() {
    if (selectedFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择2~8个文件')));
      return;
    }
  }

  void startSingleThreadCompare() {
    if (selectedFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择2~8个文件')));
      return;
    }
  }

  void formatToText() {
    if (selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择1个文件')));
      return;
    }
  }
}

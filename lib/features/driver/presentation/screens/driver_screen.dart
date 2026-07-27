import 'package:flutter/material.dart';

/// 基础配置页面 - MD3 风格
class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  String packageName = '未设置';
  String pid = '未获取';
  int taskBlock = 100;
  bool pidMonitor = true;

  Map<String, bool> memoryRanges = {
    'PPSSPP': false, 'Anonymous': true, 'Ashmem': false,
    'Code_app': true, 'Stack': false, 'C_bss': true,
    'Code_system': false, 'C_data': true, 'C_heap': false,
    'Java': false, 'Java_heap': false, 'Other': false,
    'Video': false, 'C_alloc': true, 'All': false, 'Bad': false,
  };

  bool singlePointer = true;
  int rwMethod = 0;
  bool handleB4 = true;
  bool pageFault = false;
  bool readNonR = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基础配置'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: resetConfig),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 进程状态
            _buildProcessCard(),
            const SizedBox(height: 16),

            // 内存范围
            _buildMemoryCard(),
            const SizedBox(height: 16),

            // 功能设置
            _buildFunctionCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 进程状态卡片
  Widget _buildProcessCard() {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.phone_android, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('进程状态', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          ListTile(
            title: const Text('进程包名'),
            subtitle: Text(packageName),
            onTap: editPackageName,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('进程PID'),
            subtitle: Text(pid),
            onTap: editPid,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('多线程分块'),
            trailing: Text('$taskBlock', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            onTap: editTaskBlock,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('进程监听'),
            subtitle: Text(pidMonitor ? '开启' : '关闭'),
            value: pidMonitor,
            onChanged: (v) => setState(() => pidMonitor = v),
          ),
        ],
      ),
    );
  }

  /// 内存范围卡片
  Widget _buildMemoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('内存范围', style: Theme.of(context).textTheme.titleMedium),
                ),
                Badge(
                  label: Text('${memoryRanges.values.where((v) => v).length}'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: memoryRanges.length,
              itemBuilder: (context, index) {
                final entry = memoryRanges.entries.elementAt(index);
                return _buildMemoryChip(entry.key, entry.value);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 内存范围芯片
  Widget _buildMemoryChip(String name, bool value) {
    return FilterChip(
      label: Text(name, style: const TextStyle(fontSize: 11)),
      selected: value,
      onSelected: (selected) {
        setState(() {
          if (name == 'All') {
            memoryRanges.updateAll((key, _) => !value);
          } else {
            memoryRanges[name] = !value;
            final allSelected = memoryRanges.entries
                .where((e) => e.key != 'All')
                .every((e) => e.value);
            memoryRanges['All'] = allSelected;
          }
        });
      },
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      showCheckmark: false,
    );
  }

  /// 功能设置卡片
  Widget _buildFunctionCard() {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('功能设置', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('指针模式'),
            subtitle: Text(singlePointer ? '单指针' : '多指针'),
            value: singlePointer,
            onChanged: (v) => setState(() => singlePointer = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('读写方式'),
            subtitle: Text(_getRwMethodName()),
            onTap: editRwMethod,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('处理B4'),
            subtitle: Text(handleB4 ? '开启' : '关闭'),
            value: handleB4,
            onChanged: (v) => setState(() => handleB4 = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('缺页处理'),
            subtitle: Text(pageFault ? '开启' : '关闭'),
            value: pageFault,
            onChanged: (v) => setState(() => pageFault = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('读非r段'),
            subtitle: Text(readNonR ? '开启' : '关闭'),
            value: readNonR,
            onChanged: (v) => setState(() => readNonR = v),
          ),
        ],
      ),
    );
  }

  String _getRwMethodName() {
    switch (rwMethod) {
      case 0: return 'SYSCALL - 系统调用';
      case 1: return 'KERNEL - 内核驱动';
      case 2: return 'PREAD64 - /proc/pid/mem';
      default: return '未知';
    }
  }

  void editPackageName() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('进程包名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '包名',
            hintText: 'com.xxx.game',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() => packageName = controller.text);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void editPid() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('进程PID'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'PID',
            hintText: '12345',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() => pid = controller.text);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void editTaskBlock() {
    showDialog(
      context: context,
      builder: (context) {
        double temp = taskBlock.toDouble();
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('多线程分块'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$taskBlock', style: Theme.of(context).textTheme.displaySmall),
                Slider(
                  value: temp,
                  min: 10,
                  max: 1000,
                  divisions: 99,
                  label: '$taskBlock',
                  onChanged: (v) => setDialog(() => temp = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  setState(() => taskBlock = temp.toInt());
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

  void editRwMethod() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('读写方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
              title: const Text('SYSCALL'),
              subtitle: const Text('系统调用，最通用'),
              value: 0,
              groupValue: rwMethod,
              onChanged: (v) {
                setState(() => rwMethod = v!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<int>(
              title: const Text('KERNEL'),
              subtitle: const Text('加载 libmemory.so'),
              value: 1,
              groupValue: rwMethod,
              onChanged: (v) {
                setState(() => rwMethod = v!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<int>(
              title: const Text('PREAD64'),
              subtitle: const Text('/proc/pid/mem'),
              value: 2,
              groupValue: rwMethod,
              onChanged: (v) {
                setState(() => rwMethod = v!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ],
      ),
    );
  }

  void resetConfig() {
    setState(() {
      packageName = '未设置';
      pid = '未获取';
      taskBlock = 100;
      pidMonitor = true;
      memoryRanges.updateAll((key, _) => false);
      singlePointer = true;
      rwMethod = 0;
      handleB4 = true;
      pageFault = false;
      readNonR = false;
    });
  }
}

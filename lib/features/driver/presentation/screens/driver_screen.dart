import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fscan/core/config/app_config.dart';
import 'package:fscan/core/network/ws_service.dart';

/// 进程数据模型
class ProcessInfo {
  final String packageName;
  final String arch;
  final int pid;

  ProcessInfo({
    required this.packageName,
    required this.arch,
    required this.pid,
  });
}

/// 基础配置页面 - MD3 风格
class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  // 进程配置
  ProcessInfo? selectedProcess;
  String pidInput = '';
  bool processMonitor = false;
  bool restartRequired = false;

  // 内存范围
  Map<String, bool> memoryRanges = {
    'Java_heap': true,    // Jh - Java Heap
    'C_heap': false,      // Ch - C++ Heap
    'C_alloc': true,      // Ca - C++ Alloc
    'C_data': true,       // Cd - C++ .data
    'C_bss': true,        // Cb - C++ .bss
    'PPSSPP': false,      // PS - PPSSPP
    'Anonymous': true,    // A - Anonymous
    'Java': false,        // J - Java
    'Stack': false,       // S - Stack
    'Ashmem': false,      // As - Ashmem
    'Video': false,       // V - Video
    'Other': false,       // O - Other
    'Bad': false,         // B - Bad
    'Code_app': true,     // Xa - Code app
    'Code_exec': false,   // Xe - Code execution
    'All': false,
  };

  // 进程列表
  List<ProcessInfo> allProcesses = [];
  bool _isLoadingProcesses = false;

  @override
  void initState() {
    super.initState();
    // 延迟到 build 完成后再加载，避免 setState during build 错误
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProcesses();
    });
  }

  /// 从服务器加载进程列表
  Future<void> _loadProcesses() async {
    if (!mounted) return;

    setState(() => _isLoadingProcesses = true);

    try {
      final wsService = context.read<WsService>();
      final processes = await wsService.getProcesses();

      if (processes != null && mounted) {
        setState(() {
          allProcesses = processes.map((p) => ProcessInfo(
            packageName: p['packageName'] ?? '',
            arch: p['arch'] ?? 'x64',
            pid: p['pid'] ?? 0,
          )).toList();
          _isLoadingProcesses = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingProcesses = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingProcesses = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基础配置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 进程配置
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

  /// 进程配置卡片
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
                Text('进程配置', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),

          // 进程包名
          ListTile(
            title: const Text('进程包名'),
            subtitle: Text(
              selectedProcess?.packageName ?? '点击选择',
              style: TextStyle(
                color: selectedProcess != null
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
            onTap: selectProcess,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 进程PID
          ListTile(
            title: const Text('进程PID'),
            subtitle: Text(
              selectedProcess != null ? '${selectedProcess!.pid}' : (pidInput.isEmpty ? '手动输入' : pidInput),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: processMonitor
                        ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
                        : Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: processMonitor ? null : refreshPid,
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: TextEditingController(text: pidInput),
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '输入PID',
                      hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      isDense: true,
                    ),
                    enabled: !processMonitor,
                    onChanged: (value) {
                      setState(() {
                        pidInput = value;
                        if (value.isNotEmpty) {
                          selectedProcess = null;
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 进程监听
          SwitchListTile(
            title: Row(
              children: [
                const Text('进程监听'),
                const SizedBox(width: 4),
                _buildHelpIcon('进程监听说明', '选中包名后，后台将开启一个线程每隔2秒获取当前选中的包名PID。\n\n'
                    '开启后不允许自己设置PID。\n\n'
                    '开启需要先设置包名，否则不允许开启。\n\n'
                    '修改后需要重启生效。'),
              ],
            ),
            subtitle: Text(processMonitor ? '开启' : '关闭'),
            value: processMonitor,
            onChanged: (v) {
              if (v && selectedProcess == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请先选择进程包名')),
                );
                return;
              }
              setState(() {
                processMonitor = v;
                restartRequired = true;
              });
            },
          ),

          // 重启提示
          if (restartRequired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '修改后需要重启生效',
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 内存范围卡片
  Widget _buildMemoryCard() {
    // 获取已选中的内存范围（保持原始顺序）
    final selectedRanges = memoryRanges.entries
        .where((e) => e.value && e.key != 'All')
        .toList();

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
                if (selectedRanges.isNotEmpty)
                  Badge(
                    label: Text('${selectedRanges.length}'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: selectMemoryRanges,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: selectedRanges.isEmpty
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('点击选择内存范围', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ],
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: selectedRanges.map((entry) {
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              radius: 10,
                              child: Text(
                                _getMemoryShortName(entry.key),
                                style: const TextStyle(fontSize: 8, color: Colors.white),
                              ),
                            ),
                            label: Text(_getMemoryFullName(entry.key), style: const TextStyle(fontSize: 12)),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () {
                              setState(() => memoryRanges[entry.key] = false);
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

  /// 获取内存范围简称
  String _getMemoryShortName(String key) {
    switch (key) {
      case 'Java_heap': return 'Jh';
      case 'C_heap': return 'Ch';
      case 'C_alloc': return 'Ca';
      case 'C_data': return 'Cd';
      case 'C_bss': return 'Cb';
      case 'PPSSPP': return 'PS';
      case 'Anonymous': return 'A';
      case 'Java': return 'J';
      case 'Stack': return 'S';
      case 'Ashmem': return 'As';
      case 'Video': return 'V';
      case 'Other': return 'O';
      case 'Bad': return 'B';
      case 'Code_app': return 'Xa';
      case 'Code_exec': return 'Xe';
      case 'All': return 'Al';
      default: return key.substring(0, 2);
    }
  }

  /// 获取内存范围全称
  String _getMemoryFullName(String key) {
    switch (key) {
      case 'Java_heap': return 'Java Heap';
      case 'C_heap': return 'C++ Heap';
      case 'C_alloc': return 'C++ Alloc';
      case 'C_data': return 'C++ .data';
      case 'C_bss': return 'C++ .bss';
      case 'PPSSPP': return 'PPSSPP';
      case 'Anonymous': return 'Anonymous';
      case 'Java': return 'Java';
      case 'Stack': return 'Stack';
      case 'Ashmem': return 'Ashmem';
      case 'Video': return 'Video';
      case 'Other': return 'Other';
      case 'Bad': return 'Bad';
      case 'Code_app': return 'Code app';
      case 'Code_exec': return 'Code execution';
      case 'All': return 'All';
      default: return key;
    }
  }

  /// 选择内存范围弹窗
  void selectMemoryRanges() {
    Map<String, bool> tempSelected = Map.from(memoryRanges);
    String searchText = '';

    // 在打开弹窗时排序一次，本次弹窗期间保持这个顺序
    var sortedEntries = tempSelected.entries.toList();
    sortedEntries.sort((a, b) {
      if (a.key == 'All') return -1;
      if (b.key == 'All') return 1;
      if (a.value && !b.value) return -1;
      if (!a.value && b.value) return 1;
      return 0;
    });

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            // 搜索筛选（不重新排序）
            var filteredEntries = sortedEntries.where((entry) {
              return entry.key.toLowerCase().contains(searchText.toLowerCase()) ||
                  _getMemoryFullName(entry.key).toLowerCase().contains(searchText.toLowerCase());
            }).toList();

            // 统计已选数量（不含All）
            final selectedCount = tempSelected.entries
                .where((e) => e.key != 'All' && e.value)
                .length;

            return AlertDialog(
              title: Row(
                children: [
                  const Text('选择内存范围'),
                  const Spacer(),
                  Text(
                    '$selectedCount/${tempSelected.length - 1}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
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
                        hintText: '搜索...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setDialog(() => searchText = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    // 列表
                    Expanded(
                      child: filteredEntries.isEmpty
                          ? Center(
                              child: Text(
                                '没有找到匹配项',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredEntries.length,
                              itemBuilder: (context, index) {
                                final entry = filteredEntries[index];
                                return CheckboxListTile(
                                  value: tempSelected[entry.key],
                                  onChanged: (selected) {
                                    setDialog(() {
                                      if (entry.key == 'All') {
                                        tempSelected.updateAll((key, _) => !tempSelected['All']!);
                                      } else {
                                        tempSelected[entry.key] = !tempSelected[entry.key]!;
                                        final allSelected = tempSelected.entries
                                            .where((e) => e.key != 'All')
                                            .every((e) => e.value);
                                        tempSelected['All'] = allSelected;
                                      }
                                    });
                                  },
                                  title: Text(
                                    _getMemoryFullName(entry.key),
                                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    _getMemoryShortName(entry.key),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                  secondary: CircleAvatar(
                                    backgroundColor: tempSelected[entry.key] == true
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                                    radius: 14,
                                    child: Text(
                                      _getMemoryShortName(entry.key),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: tempSelected[entry.key] == true
                                            ? Colors.white
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  dense: true,
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
                    setState(() => memoryRanges = tempSelected);
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

  /// 功能设置卡片
  Widget _buildFunctionCard() {
    final appConfig = context.watch<AppConfig>();

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
          // 读写方式
          ListTile(
            title: const Text('读写方式'),
            subtitle: Text(appConfig.getRwMethodName()),
            onTap: editRwMethod,
          ),

          // 动态库地址（始终显示）
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('动态库地址'),
            subtitle: Text(
              appConfig.libPath,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 检测按钮
                IconButton(
                  icon: Icon(Icons.bug_report, color: Theme.of(context).colorScheme.primary),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('检测功能开发中...')),
                    );
                  },
                  tooltip: '检测',
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
            onTap: editLibPath,
          ),
        ],
      ),
    );
  }

  /// 选择进程弹窗
  void selectProcess() {
    String searchText = '';
    ProcessInfo? tempSelected = selectedProcess;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            final filteredProcesses = allProcesses.where((process) {
              return process.packageName.toLowerCase().contains(searchText.toLowerCase());
            }).toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Text('选择进程'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _isLoadingProcesses
                        ? null
                        : () async {
                            setDialog(() => _isLoadingProcesses = true);
                            await _loadProcesses();
                            setDialog(() {});
                          },
                    tooltip: '刷新进程列表',
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: '搜索进程...',
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
                      child: _isLoadingProcesses
                          ? const Center(child: CircularProgressIndicator())
                          : filteredProcesses.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      const SizedBox(height: 16),
                                      Text('暂无进程', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                      const SizedBox(height: 8),
                                      Text('请先连接服务器并刷新', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                    ],
                                  ),
                                )
                              : RadioGroup<ProcessInfo>(
                                  groupValue: tempSelected,
                                  onChanged: (value) {
                                    setDialog(() => tempSelected = value);
                                  },
                                  child: ListView.builder(
                                    itemCount: filteredProcesses.length,
                                    itemBuilder: (context, index) {
                                      final process = filteredProcesses[index];
                                      return RadioListTile<ProcessInfo>(
                                        value: process,
                                        title: Text(
                                          process.packageName,
                                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                        ),
                                        subtitle: Text('${process.arch} | PID: ${process.pid}'),
                                        secondary: CircleAvatar(
                                          backgroundColor: Theme.of(context).colorScheme.primary,
                                          radius: 14,
                                          child: Text(
                                            process.arch == 'x64' ? '64' : '32',
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
                  onPressed: tempSelected == null
                      ? null
                      : () async {
                          setState(() {
                            selectedProcess = tempSelected;
                            pidInput = tempSelected?.pid.toString() ?? '';
                            restartRequired = true;
                          });

                          // 通知 AppConfig 选中的进程
                          final appConfig = context.read<AppConfig>();
                          final wsService = context.read<WsService>();
                          appConfig.setSelectedProcess(
                            tempSelected?.packageName,
                            tempSelected?.pid,
                          );

                          // 从服务器获取模块并加载
                          await appConfig.fetchAndLoadModules(
                            wsService,
                            tempSelected?.packageName,
                          );

                          if (mounted && context.mounted) {
                            Navigator.pop(context);
                          }
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

  /// 刷新PID
  void refreshPid() {
    if (selectedProcess == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择进程包名')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在获取 ${selectedProcess!.packageName} 的PID...')),
    );
  }

  /// 帮助图标
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

  void editRwMethod() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('读写方式'),
        content: RadioGroup<int>(
          groupValue: context.read<AppConfig>().rwMethod,
          onChanged: (v) {
            context.read<AppConfig>().setRwMethod(v!);
            Navigator.pop(context);
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<int>(
                title: Text('SYSCALL'),
                subtitle: Text('系统调用，最通用'),
                value: 0,
              ),
              RadioListTile<int>(
                title: Text('PREAD64'),
                subtitle: Text('/proc/pid/mem'),
                value: 1,
              ),
              RadioListTile<int>(
                title: Text('CUSTOM'),
                subtitle: Text('自定义动态库'),
                value: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ],
      ),
    );
  }

  void editLibPath() {
    final appConfig = context.read<AppConfig>();
    final controller = TextEditingController(text: appConfig.libPath);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('动态库地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '/data/local/tmp/libmemory.so',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              appConfig.setLibPath(controller.text);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

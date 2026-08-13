import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fscan/core/services/module_service.dart';
import 'package:fscan/core/network/ws_service.dart';
import 'package:fscan/core/utils/logger.dart';

/// 全局配置状态
class AppConfig extends ChangeNotifier {
  // 读写方式: 0=SYSCALL, 1=PREAD64, 2=CUSTOM
  int _rwMethod = 0;
  int get rwMethod => _rwMethod;

  // 动态库地址
  String _libPath = '/data/local/tmp/libsyscall.so';
  String get libPath => _libPath;

  // 配置文件目录
  String _configPath = '/sdcard/fscan/config';
  String get configPath => _configPath;

  // 扫描数据目录
  String _dataPath = '/sdcard/fscan/data';
  String get dataPath => _dataPath;

  // 进程包名
  String? _selectedPackageName;
  String? get selectedPackageName => _selectedPackageName;

  // 进程PID
  int? _selectedPid;
  int? get selectedPid => _selectedPid;

  // 进程监听
  bool _processMonitor = false;
  bool get processMonitor => _processMonitor;

  // ========== 模块状态 ==========
  // 服务器返回的所有可用模块
  List<ModuleItem> _availableModules = [];
  List<ModuleItem> get availableModules => _availableModules;

  // 用户选中的模块（会持久化保存）
  List<ModuleItem> _selectedModules = [];
  List<ModuleItem> get selectedModules => _selectedModules;

  // 模块加载状态
  bool _modulesLoading = false;
  bool get modulesLoading => _modulesLoading;

  // 模块是否已加载
  bool _modulesLoaded = false;
  bool get modulesLoaded => _modulesLoaded;

  // 内存范围配置
  Map<String, bool> _memoryRanges = {
    'Anonymous': true,
    'C_alloc': true,
    'C_data': true,
    'C_bss': true,
    'C_heap': false,
    'Java_heap': true,
    'Java': false,
    'Stack': false,
    'Video': false,
    'Code_app': true,
    'Code_system': false,
    'Ashmem': false,
    'Other': false,
    'Bad': false,
    'PPSSPP': false,
    'All': false,
  };
  Map<String, bool> get memoryRanges => _memoryRanges;

  /// 初始化，从本地存储加载
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _configPath = prefs.getString('app_configPath') ?? '/sdcard/fscan/config';
    _dataPath = prefs.getString('app_dataPath') ?? '/sdcard/fscan/data';

    // 加载读写方式和动态库路径
    _rwMethod = prefs.getInt('app_rwMethod') ?? 0;
    _libPath = prefs.getString('app_libPath') ?? '/data/local/tmp/libsyscall.so';

    // 加载内存范围配置
    final savedRanges = prefs.getString('app_memoryRanges');
    if (savedRanges != null) {
      try {
        // 解析保存的内存范围
        // 格式: {Anonymous: true, C_alloc: true, ...}
        final cleaned = savedRanges.replaceAll('{', '').replaceAll('}', '');
        for (var item in cleaned.split(', ')) {
          final parts = item.split(': ');
          if (parts.length == 2) {
            final key = parts[0].trim();
            final value = parts[1].trim() == 'true';
            if (_memoryRanges.containsKey(key)) {
              _memoryRanges[key] = value;
            }
          }
        }
      } catch (e) {
        // 解析失败，使用默认值
        logger.warning('AppConfig', '解析内存范围配置失败: $e');
      }
    }

    // 加载保存的进程配置
    final savedPackage = prefs.getString('selected_process_package');
    final savedPid = prefs.getInt('selected_process_pid') ?? 0;

    if (savedPackage != null && savedPackage.isNotEmpty) {
      _selectedPackageName = savedPackage;
      _selectedPid = savedPid;
      logger.info('AppConfig', '加载保存的进程配置: $savedPackage (PID: $savedPid)');
    }

    notifyListeners();
  }

  /// 设置读写方式
  Future<void> setRwMethod(int method) async {
    _rwMethod = method;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_rwMethod', method);
  }

  /// 设置动态库地址
  Future<void> setLibPath(String path) async {
    _libPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_libPath', path);
  }

  /// 设置内存范围
  Future<void> setMemoryRanges(Map<String, bool> ranges) async {
    _memoryRanges = Map.from(ranges);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // 保存为JSON字符串
    await prefs.setString('app_memoryRanges', ranges.toString());
  }

  /// 切换单个内存范围
  Future<void> toggleMemoryRange(String key) async {
    _memoryRanges[key] = !(_memoryRanges[key] ?? false);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_memoryRanges', _memoryRanges.toString());
  }

  /// 设置配置文件目录
  Future<void> setConfigPath(String path) async {
    _configPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_configPath', path);
  }

  /// 设置扫描数据目录
  Future<void> setDataPath(String path) async {
    _dataPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_dataPath', path);
  }

  /// 设置选中的进程
  void setSelectedProcess(String? packageName, int? pid) {
    _selectedPackageName = packageName;
    _selectedPid = pid;
    notifyListeners();
  }

  /// 设置进程监听
  void setProcessMonitor(bool enabled) {
    _processMonitor = enabled;
    notifyListeners();
  }

  /// 获取读写方式名称
  String getRwMethodName() {
    switch (_rwMethod) {
      case 0: return 'SYSCALL';
      case 1: return 'PREAD64';
      case 2: return 'CUSTOM';
      default: return '未知';
    }
  }

  /// 是否可以读取受限内存（需要PREAD64或CUSTOM）
  bool get canReadProtected => _rwMethod == 1 || _rwMethod == 2;

  // ========== 模块相关方法 ==========

  /// 设置用户选中的模块
  void setSelectedModules(List<ModuleItem> modules) {
    _selectedModules = modules;
    notifyListeners();
  }

  /// 设置模块加载状态
  void setModulesLoading(bool loading) {
    _modulesLoading = loading;
    notifyListeners();
  }

  /// 设置模块已加载标记
  void setModulesLoaded(bool loaded) {
    _modulesLoaded = loaded;
    notifyListeners();
  }

  /// 从服务器获取模块并加载（恢复用户之前的选中状态）
  Future<void> fetchAndLoadModules(WsService wsService, String? packageName) async {
    if (packageName == null) {
      _availableModules = [];
      _selectedModules = [];
      _modulesLoaded = false;
      notifyListeners();
      return;
    }

    _modulesLoading = true;
    notifyListeners();

    try {
      // 从服务器获取所有可用模块
      final serverModules = await wsService.getModules(packageName);

      if (serverModules != null && serverModules.isNotEmpty) {
        // 将服务器返回的数据转换为可用模块列表
        _availableModules = serverModules.map((m) => ModuleItem(
          name: m['name'] ?? '',
          index: m['index'] ?? '',
          type: m['type'] ?? '',
          startAddress: m['startAddress'] ?? '',
          endAddress: m['endAddress'] ?? '',
        )).toList();
      } else {
        _availableModules = [];
      }

      // 从本地加载用户之前选中的模块
      final savedModules = await ModuleService.loadModules(packageName);

      // 只保留仍然在可用模块列表中的（只匹配 name, index, type，不匹配地址）
      _selectedModules = savedModules.where((saved) {
        return _availableModules.any((available) =>
          available.name == saved.name &&
          available.index == saved.index &&
          available.type == saved.type
        );
      }).toList();

      _modulesLoaded = true;
    } catch (e) {
      // 出错时清空
      _availableModules = [];
      _selectedModules = [];
      _modulesLoaded = true;
    } finally {
      _modulesLoading = false;
      notifyListeners();
    }
  }

  /// 保存用户选中的模块到本地
  Future<void> saveModulesForPackage(String? packageName, List<ModuleItem> modules) async {
    if (packageName == null) return;

    try {
      await ModuleService.saveModules(packageName, modules);
    } catch (e) {
      // 保存失败时静默处理
    }
  }
}

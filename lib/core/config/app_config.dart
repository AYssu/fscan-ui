import 'package:flutter/foundation.dart';
import 'package:fscan/core/services/module_service.dart';
import 'package:fscan/core/network/ws_service.dart';

/// 全局配置状态
class AppConfig extends ChangeNotifier {
  // 读写方式: 0=SYSCALL, 1=PREAD64, 2=CUSTOM
  int _rwMethod = 0;
  int get rwMethod => _rwMethod;

  // 动态库地址
  String _libPath = '/data/local/tmp/libmemory.so';
  String get libPath => _libPath;

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

  /// 设置读写方式
  void setRwMethod(int method) {
    _rwMethod = method;
    notifyListeners();
  }

  /// 设置动态库地址
  void setLibPath(String path) {
    _libPath = path;
    notifyListeners();
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

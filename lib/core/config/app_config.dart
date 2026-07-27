import 'package:flutter/foundation.dart';

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
}

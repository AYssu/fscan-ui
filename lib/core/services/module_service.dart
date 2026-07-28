import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// 从 JSON 创建 ModuleItem
  factory ModuleItem.fromJson(Map<String, dynamic> json) {
    return ModuleItem(
      name: json['name'] as String,
      index: json['index'] as String,
      type: json['type'] as String,
      startAddress: json['startAddress'] as String,
      endAddress: json['endAddress'] as String,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'index': index,
      'type': type,
      'startAddress': startAddress,
      'endAddress': endAddress,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModuleItem &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          index == other.index &&
          type == other.type;

  @override
  int get hashCode => name.hashCode ^ index.hashCode ^ type.hashCode;
}

/// 模块持久化服务
/// 使用 SharedPreferences 存储模块配置，支持所有平台
class ModuleService {
  static const String _prefix = 'modules_';
  static const String _packageListKey = 'modules_package_list';

  /// 读取指定包名的模块配置
  static Future<List<ModuleItem>> loadModules(String packageName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('$_prefix$packageName');
      if (jsonString == null || jsonString.isEmpty) return [];
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((json) => ModuleItem.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存模块配置到指定包名
  static Future<void> saveModules(String packageName, List<ModuleItem> modules) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = modules.map((m) => m.toJson()).toList();
    await prefs.setString('$_prefix$packageName', json.encode(jsonList));

    // 更新包名列表
    await _updatePackageList(packageName);
  }

  /// 删除指定包名的模块配置
  static Future<void> deleteModules(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$packageName');
    await _removeFromPackageList(packageName);
  }

  /// 获取所有已保存模块配置的包名列表
  static Future<List<String>> getSavedPackageNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_packageListKey) ?? [];
  }

  /// 更新包名列表
  static Future<void> _updatePackageList(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_packageListKey) ?? [];
    if (!list.contains(packageName)) {
      list.add(packageName);
      await prefs.setStringList(_packageListKey, list);
    }
  }

  /// 从包名列表中移除
  static Future<void> _removeFromPackageList(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_packageListKey) ?? [];
    list.remove(packageName);
    await prefs.setStringList(_packageListKey, list);
  }
}

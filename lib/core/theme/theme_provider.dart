import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题状态管理
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  Color _seedColor = Colors.blue;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// 初始化，从本地存储加载
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? true;
    final colorValue = prefs.getInt('seedColor') ?? Colors.blue.toARGB32();
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _seedColor = Color(colorValue);
    notifyListeners();
  }

  /// 切换主题
  Future<void> toggleTheme() async {
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
  }

  /// 设置主题
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
  }

  /// 设置主题颜色
  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('seedColor', color.toARGB32());
  }
}

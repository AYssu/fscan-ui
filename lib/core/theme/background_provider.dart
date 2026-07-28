import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局背景状态管理
class BackgroundProvider extends ChangeNotifier {
  String? _imagePath;
  double _opacity = 0.3;
  double _cardOpacity = 0.85;

  String? get imagePath => _imagePath;
  double get opacity => _opacity;
  double get cardOpacity => _cardOpacity;
  bool get hasBackground => _imagePath != null && _imagePath!.isNotEmpty;

  /// 初始化，从本地存储加载
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _imagePath = prefs.getString('bg_imagePath');
    _opacity = prefs.getDouble('bg_opacity') ?? 0.3;
    _cardOpacity = prefs.getDouble('bg_cardOpacity') ?? 0.85;
    // 验证文件是否还存在
    if (_imagePath != null && !await File(_imagePath!).exists()) {
      _imagePath = null;
    }
    notifyListeners();
  }

  /// 设置背景图片
  Future<void> setImage(String? path) async {
    _imagePath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString('bg_imagePath', path);
    } else {
      await prefs.remove('bg_imagePath');
    }
  }

  /// 设置背景透明度
  Future<void> setOpacity(double value) async {
    _opacity = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bg_opacity', value);
  }

  /// 设置卡片透明度
  Future<void> setCardOpacity(double value) async {
    _cardOpacity = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bg_cardOpacity', value);
  }

  /// 清除背景
  Future<void> clear() async {
    _imagePath = null;
    _opacity = 0.3;
    _cardOpacity = 0.85;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bg_imagePath');
    await prefs.remove('bg_opacity');
    await prefs.remove('bg_cardOpacity');
  }
}

import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

/// 缓存管理工具
class CacheUtils {
  /// 计算总缓存大小（字节）
  static Future<int> getCacheSize() async {
    int total = 0;

    // SharedPreferences 数据大小
    total += await _getSharedPreferencesSize();

    // 日志文件大小
    total += await _getDirectorySize('logs');

    // 头像缓存大小
    total += await _getDirectorySize('avatars');

    return total;
  }

  /// 获取 SharedPreferences 中所有数据的字节大小
  static Future<int> _getSharedPreferencesSize() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    int size = 0;
    for (final key in keys) {
      final value = prefs.get(key);
      size += key.length * 2; // key 的 UTF-16 大小
      if (value is String) {
        size += value.length * 2;
      } else if (value is bool) {
        size += 1;
      } else if (value is int) {
        size += 8;
      } else if (value is double) {
        size += 8;
      } else if (value is List<String>) {
        for (final s in value) {
          size += s.length * 2;
        }
      }
    }
    return size;
  }

  /// 获取指定子目录下所有文件的大小
  static Future<int> _getDirectorySize(String subDir) async {
    try {
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/$subDir',
      );
      if (!await dir.exists()) return 0;

      int size = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
      return size;
    } catch (e) {
      return 0;
    }
  }

  /// 清空所有缓存（保留主题偏好和背景设置）
  static Future<void> clearAllCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    // 需要保留的设置
    final keepKeys = {'isDarkMode', 'seedColor', 'bg_imagePath', 'bg_opacity', 'bg_cardOpacity', 'ws_url', 'app_configPath', 'app_dataPath'};

    for (final key in keys) {
      if (!keepKeys.contains(key)) {
        await prefs.remove(key);
      }
    }

    // 清空日志文件
    await _clearDirectory('logs');

    // 清空头像缓存
    await _clearDirectory('avatars');
  }

  /// 清空指定子目录下的所有文件（保留目录本身）
  static Future<void> _clearDirectory(String subDir) async {
    try {
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/$subDir',
      );
      if (!await dir.exists()) return;

      await for (final entity in dir.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    } catch (e) {
      // 忽略清理错误
    }
  }

  /// 格式化文件大小为可读字符串
  static String formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

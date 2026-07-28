import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
  fatal,
}

/// 日志条目
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'tag': tag,
    'message': message,
    'error': error?.toString(),
    'stackTrace': stackTrace?.toString(),
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp']),
      level: LogLevel.values.firstWhere(
        (e) => e.name == json['level'],
        orElse: () => LogLevel.info,
      ),
      tag: json['tag'] ?? '',
      message: json['message'] ?? '',
      error: json['error'],
      stackTrace: json['stackTrace'] != null ? StackTrace.fromString(json['stackTrace']) : null,
    );
  }

  @override
  String toString() {
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final levelStr = level.name.toUpperCase().padRight(7);
    return '[$timeStr] [$levelStr] [$tag] $message';
  }
}

/// 日志管理器
class Logger extends ChangeNotifier {
  static Logger? _instance;
  static Logger get instance => _instance ??= Logger._();

  Logger._();

  final List<LogEntry> _logs = [];
  LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
  bool _enableFileLogging = true;
  File? _logFile;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  LogLevel get minLevel => _minLevel;
  bool get enableFileLogging => _enableFileLogging;

  /// 初始化日志系统
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    final dateStr = DateTime.now().toIso8601String().split('T')[0];
    _logFile = File('${logDir.path}/$dateStr.log');

    // 加载今日日志
    await _loadLogs();

    info('Logger', '日志系统初始化完成');
  }

  /// 加载日志文件
  Future<void> _loadLogs() async {
    if (_logFile == null || !await _logFile!.exists()) return;

    try {
      final content = await _logFile!.readAsString();
      if (content.isNotEmpty) {
        final lines = content.split('\n').where((l) => l.isNotEmpty).toList();
        for (final line in lines) {
          try {
            final json = jsonDecode(line);
            _logs.add(LogEntry.fromJson(json));
          } catch (e) {
            // 忽略解析失败的行
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load logs: $e');
    }
  }

  /// 写入日志到文件
  Future<void> _writeToFile(LogEntry entry) async {
    if (!_enableFileLogging || _logFile == null) return;

    try {
      final line = jsonEncode(entry.toJson());
      await _logFile!.writeAsString('$line\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('Failed to write log: $e');
    }
  }

  /// 添加日志
  void _log(LogLevel level, String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    if (level.index < _minLevel.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    _logs.add(entry);

    // 保持日志数量在合理范围
    if (_logs.length > 1000) {
      _logs.removeRange(0, _logs.length - 1000);
    }

    // 控制台输出
    if (kDebugMode) {
      debugPrint(entry.toString());
    }

    // 写入文件
    _writeToFile(entry);

    // 通知监听器
    notifyListeners();
  }

  void debug(String tag, String message) => _log(LogLevel.debug, tag, message);
  void info(String tag, String message) => _log(LogLevel.info, tag, message);
  void warning(String tag, String message) => _log(LogLevel.warning, tag, message);
  void error(String tag, String message, [dynamic error, StackTrace? stackTrace]) =>
      _log(LogLevel.error, tag, message, error, stackTrace);
  void fatal(String tag, String message, [dynamic error, StackTrace? stackTrace]) =>
      _log(LogLevel.fatal, tag, message, error, stackTrace);

  /// 设置最低日志级别
  void setMinLevel(LogLevel level) {
    _minLevel = level;
    notifyListeners();
  }

  /// 启用/禁用文件日志
  void setEnableFileLogging(bool enable) {
    _enableFileLogging = enable;
    notifyListeners();
  }

  /// 清空日志
  Future<void> clearLogs() async {
    _logs.clear();
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
    notifyListeners();
  }

  /// 导出日志
  Future<String> exportLogs() async {
    final buffer = StringBuffer();
    for (final log in _logs) {
      buffer.writeln(log.toString());
    }
    return buffer.toString();
  }

  /// 获取日志文件路径
  Future<String> getLogFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/logs';
  }
}

/// 全局日志实例
final logger = Logger.instance;

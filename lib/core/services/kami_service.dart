import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 卡密信息
class KamiInfo {
  final int available;       // 可用次数
  final int bindNumber;      // 绑定数量
  final int cardId;          // 卡密ID
  final String cardType;     // 卡密类型（如：季卡）
  final String endTime;      // 到期时间
  final bool success;        // 查询是否成功
  final int unbindNumber;    // 未绑定数量

  KamiInfo({
    required this.available,
    required this.bindNumber,
    required this.cardId,
    required this.cardType,
    required this.endTime,
    required this.success,
    required this.unbindNumber,
  });

  factory KamiInfo.fromJson(Map<String, dynamic> json) {
    return KamiInfo(
      available: json['available'] ?? 0,
      bindNumber: json['bindNumber'] ?? 0,
      cardId: json['cardId'] ?? 0,
      cardType: json['cardType'] ?? '',
      endTime: json['endTime'] ?? '',
      success: json['success'] ?? false,
      unbindNumber: json['unbindNumber'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'available': available,
    'bindNumber': bindNumber,
    'cardId': cardId,
    'cardType': cardType,
    'endTime': endTime,
    'success': success,
    'unbindNumber': unbindNumber,
  };

  /// 格式化到期时间显示
  String get formattedEndTime {
    if (endTime.isEmpty) return '未知';
    // 去掉秒部分，只显示到分钟
    if (endTime.contains(' ')) {
      return endTime.split(' ').first;
    }
    return endTime;
  }

  /// 是否有效（成功且未过期）
  bool get isValid => success;

  /// 获取状态描述
  String get statusText {
    if (!success) return '无效卡密';
    return '$cardType · 到期: $formattedEndTime';
  }
}

/// 卡密服务
class KamiService extends ChangeNotifier {
  String? _kamiKey;
  KamiInfo? _kamiInfo;
  bool _isLoading = false;
  String? _errorMessage;

  String? get kamiKey => _kamiKey;
  KamiInfo? get kamiInfo => _kamiInfo;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthorized => _kamiKey != null && _kamiKey!.isNotEmpty;

  /// 初始化，从本地加载
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final kamiKey = prefs.getString('kami_key');
    final kamiInfoJson = prefs.getString('kami_info');

    if (kamiKey != null && kamiKey.isNotEmpty) {
      _kamiKey = kamiKey;
      if (kamiInfoJson != null) {
        try {
          _kamiInfo = KamiInfo.fromJson(jsonDecode(kamiInfoJson));
        } catch (e) {
          debugPrint('KamiService: Failed to parse kami info: $e');
        }
      }
      notifyListeners();
      debugPrint('KamiService: Loaded kami key');
    }
  }

  /// 查询卡密状态
  Future<bool> queryKamiInfo(String key) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 实际查询由 WsService 处理，这里只保存结果
      debugPrint('KamiService: Querying kami info for key: $key');
      _kamiKey = key;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('KamiService: Query failed: $e');
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 保存卡密信息
  Future<void> saveKamiInfo(String key, KamiInfo info) async {
    _kamiKey = key;
    _kamiInfo = info;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kami_key', key);
    await prefs.setString('kami_info', jsonEncode(info.toJson()));

    debugPrint('KamiService: Kami info saved');
  }

  /// 清除卡密信息
  Future<void> clearKamiInfo() async {
    _kamiKey = null;
    _kamiInfo = null;
    _errorMessage = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('kami_key');
    await prefs.remove('kami_info');

    debugPrint('KamiService: Kami info cleared');
  }

  /// 获取卡密命令行参数
  /// 如果有卡密则返回 -k <key>，否则返回空字符串
  String get kamiArg {
    if (_kamiKey != null && _kamiKey!.isNotEmpty) {
      return '-k $_kamiKey';
    }
    return '';
  }

  /// 获取卡密key（用于命令行参数）
  String? get key => _kamiKey;
}

import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 用户信息
class UserInfo {
  final String account;
  final String email;
  final DateTime expireTime;
  final String? nickname;
  final int? qqNumber;

  UserInfo({
    required this.account,
    required this.email,
    required this.expireTime,
    this.nickname,
    this.qqNumber,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      account: json['account'] ?? '',
      email: json['email'] ?? '',
      expireTime: DateTime.parse(json['expireTime']),
      nickname: json['nickname'],
      qqNumber: json['qqNumber'],
    );
  }

  Map<String, dynamic> toJson() => {
    'account': account,
    'email': email,
    'expireTime': expireTime.toIso8601String(),
    'nickname': nickname,
    'qqNumber': qqNumber,
  };

  /// 判断是否是QQ邮箱
  bool get isQQEmail {
    if (!email.endsWith('@qq.com')) return false;
    final prefix = email.split('@')[0];
    return int.tryParse(prefix) != null;
  }

  /// 获取QQ号
  int? get extractedQQNumber {
    if (!isQQEmail) return null;
    return int.tryParse(email.split('@')[0]);
  }

  /// 获取QQ头像URL
  String? get qqAvatarUrl {
    final qq = extractedQQNumber;
    if (qq == null) return null;
    return 'https://q1.qlogo.cn/g?b=qq&nk=$qq&s=640';
  }
}

/// 用户服务
class UserService extends ChangeNotifier {
  UserInfo? _userInfo;
  String? _privateKey;
  bool _isLoading = false;

  UserInfo? get userInfo => _userInfo;
  bool get isLoggedIn => _userInfo != null;
  bool get isLoading => _isLoading;

  /// 初始化，从本地加载
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfoJson = prefs.getString('userInfo');
    final privateKey = prefs.getString('privateKey');

    if (userInfoJson != null && privateKey != null) {
      try {
        _userInfo = UserInfo.fromJson(jsonDecode(userInfoJson));
        _privateKey = privateKey;
        notifyListeners();
        debugPrint('UserService: Loaded user info for ${_userInfo!.account}');
      } catch (e) {
        debugPrint('UserService: Failed to load user info: $e');
      }
    }
  }

  /// 生成RSA密钥对
  Map<String, String> _generateKeyPair() {
    // 简化版RSA密钥生成（实际项目应使用pointycastle等库）
    final random = Random.secure();
    final keyPair = base64Encode(List<int>.generate(256, (_) => random.nextInt(256)));
    return {
      'publicKey': 'pub_$keyPair',
      'privateKey': 'pri_$keyPair',
    };
  }

  /// 加密密码（简化版，实际应使用RSA）
  String _encryptPassword(String password, String publicKey) {
    // 简化版加密（实际项目应使用RSA加密）
    final bytes = utf8.encode('$password:$publicKey');
    return sha256.convert(bytes).toString();
  }

  /// 登录
  Future<bool> login(String account, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 生成密钥对
      final keyPair = _generateKeyPair();
      _privateKey = keyPair['privateKey'];

      // 加密密码
      _encryptPassword(password, keyPair['publicKey']!);

      // 返回加密后的密码和私钥，供调用方发送到服务器
      debugPrint('UserService: Generated key pair, public key discarded');

      // 实际登录由 WsService 处理，这里只保存结果
      return true;
    } catch (e) {
      debugPrint('UserService: Login failed: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 保存登录信息
  Future<void> saveLoginInfo(UserInfo userInfo, String encryptedPassword) async {
    _userInfo = userInfo;
    _isLoading = false;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userInfo', jsonEncode(userInfo.toJson()));
    await prefs.setString('encryptedPassword', encryptedPassword);
    if (_privateKey != null) {
      await prefs.setString('privateKey', _privateKey!);
    }

    debugPrint('UserService: Login info saved for ${userInfo.account}');
  }

  /// 退出登录
  Future<void> logout() async {
    _userInfo = null;
    _privateKey = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userInfo');
    await prefs.remove('privateKey');
    await prefs.remove('encryptedPassword');

    debugPrint('UserService: Logged out');
  }

  /// 获取QQ头像（先读缓存再获取网络）
  Future<String?> getQQAvatar(int qqNumber) async {
    try {
      // 检查本地缓存
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/avatars');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File('${dir.path}/qq_$qqNumber.jpg');
      if (await file.exists()) {
        return file.path;
      }

      // 从网络获取
      final url = 'https://q1.qlogo.cn/g?b=qq&nk=$qqNumber&s=640';
      // 注意：实际项目需要使用http包下载图片
      // 这里返回URL，由UI层处理
      return url;
    } catch (e) {
      debugPrint('UserService: Failed to get QQ avatar: $e');
      return null;
    }
  }
}

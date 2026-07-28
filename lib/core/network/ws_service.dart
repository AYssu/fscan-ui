import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:fscan/core/utils/logger.dart';

/// WebSocket 连接状态
enum WsStatus {
  disconnected, // 未连接
  connecting,   // 连接中
  connected,    // 已连接
  reconnecting, // 重连中
}

/// WebSocket 消息类型
enum WsMessageType {
  heartbeat,    // 心跳
  command,      // 指令
  response,     // 响应
  error,        // 错误
}

/// WebSocket 消息
class WsMessage {
  final WsMessageType type;
  final dynamic data;
  final String? id;

  WsMessage({required this.type, this.data, this.id});

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'data': data,
    'id': id,
  };

  factory WsMessage.fromJson(Map<String, dynamic> json) {
    return WsMessage(
      type: WsMessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => WsMessageType.response,
      ),
      data: json['data'],
      id: json['id'],
    );
  }

  String encode() => jsonEncode(toJson());

  factory WsMessage.decode(String source) {
    return WsMessage.fromJson(jsonDecode(source));
  }
}

/// WebSocket 服务
class WsService extends ChangeNotifier {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  StreamSubscription? _subscription;

  WsStatus _status = WsStatus.disconnected;
  String? _url;
  String? _errorMessage;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration reconnectDelay = Duration(seconds: 3);

  // 消息流控制器
  final StreamController<WsMessage> _messageController =
      StreamController<WsMessage>.broadcast();

  // 回调
  Function(WsMessage)? onMessage;
  Function(String)? onError;
  Function()? onConnected;
  Function()? onDisconnected;

  // Getters
  WsStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == WsStatus.connected;
  Stream<WsMessage> get messageStream => _messageController.stream;

  /// 连接到 WebSocket 服务器
  Future<void> connect(String url) async {
    if (_status == WsStatus.connecting || _status == WsStatus.connected) {
      return;
    }

    _url = url;
    _status = WsStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    logger.info('WebSocket', '正在连接到: $url');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      // 监听消息
      _subscription = _channel!.stream.listen(
        (data) {
          _handleMessage(data);
        },
        onError: (error) {
          _handleError(error.toString());
        },
        onDone: () {
          _handleDisconnected();
        },
      );

      // 等待连接建立
      await _channel!.ready;

      _status = WsStatus.connected;
      _reconnectAttempts = 0;
      notifyListeners();

      // 启动心跳
      _startHeartbeat();

      onConnected?.call();

      logger.info('WebSocket', '连接成功: $url');
    } catch (e) {
      logger.error('WebSocket', '连接失败: $url', e);
      _handleError(e.toString());
    }
  }

  /// 断开连接
  void disconnect() {
    _stopHeartbeat();
    _stopReconnect();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _status = WsStatus.disconnected;
    _errorMessage = null;
    notifyListeners();

    onDisconnected?.call();
    logger.info('WebSocket', '已断开连接');
  }

  /// 发送消息
  void send(WsMessage message) {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法发送消息');
      return;
    }

    try {
      _channel?.sink.add(message.encode());
      logger.debug('WebSocket', '发送消息: ${message.encode()}');
    } catch (e) {
      logger.error('WebSocket', '发送失败', e);
      _handleError('Send failed: $e');
    }
  }

  /// 发送指令
  void sendCommand(String command, {Map<String, dynamic>? params}) {
    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': command,
        'params': params,
      },
      id: DateTime.now().millisecondsSinceEpoch.toString(),
    ));
  }

  /// 发送登录请求
  Future<WsMessage?> sendLogin(String account, String encryptedPassword) async {
    final completer = Completer<WsMessage?>();

    // 监听登录响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _loginRequestId) {
        completer.complete(message);
        subscription.cancel();
      }
    });

    _loginRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'login',
        'params': {
          'account': account,
          'password': encryptedPassword,
        },
      },
      id: _loginRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  String? _loginRequestId;

  /// 处理收到的消息
  void _handleMessage(dynamic data) {
    try {
      final message = WsMessage.decode(data.toString());
      logger.debug('WebSocket', '收到消息: ${message.type}');

      if (message.type == WsMessageType.heartbeat) {
        // 心跳响应，不做处理
        logger.debug('WebSocket', '收到心跳响应');
        return;
      }

      _messageController.add(message);
      onMessage?.call(message);
    } catch (e) {
      logger.error('WebSocket', '消息解析失败', e);
    }
  }

  /// 处理错误
  void _handleError(String error) {
    _errorMessage = error;
    _status = WsStatus.disconnected;
    notifyListeners();

    onError?.call(error);
    logger.error('WebSocket', '错误: $error');

    // 尝试重连
    _tryReconnect();
  }

  /// 处理断开连接
  void _handleDisconnected() {
    if (_status == WsStatus.connected) {
      _status = WsStatus.disconnected;
      notifyListeners();
      onDisconnected?.call();
      logger.warning('WebSocket', '服务器断开连接');

      // 尝试重连
      _tryReconnect();
    }
  }

  /// 尝试重连
  void _tryReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      logger.error('WebSocket', '重连次数已达上限');
      _errorMessage = '连接失败，请检查网络后重试';
      notifyListeners();
      return;
    }

    _status = WsStatus.reconnecting;
    notifyListeners();

    _reconnectTimer = Timer(reconnectDelay, () {
      _reconnectAttempts++;
      logger.info('WebSocket', '正在重连... ($_reconnectAttempts/$maxReconnectAttempts)');
      connect(_url!);
    });
  }

  /// 停止重连
  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
  }

  /// 启动心跳
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (isConnected) {
        send(WsMessage(type: WsMessageType.heartbeat));
      }
    });
  }

  /// 停止心跳
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    super.dispose();
  }
}

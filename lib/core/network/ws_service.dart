import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  stream,       // 流式输出
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
  static const Duration heartbeatInterval = Duration(seconds: 10);
  static const Duration reconnectDelay = Duration(seconds: 3);

  // 消息流控制器
  final StreamController<WsMessage> _messageController =
      StreamController<WsMessage>.broadcast();

  // 状态流控制器
  final StreamController<WsStatus> _statusController =
      StreamController<WsStatus>.broadcast();

  // 回调
  Function(WsMessage)? onMessage;
  Function(String)? onError;
  Function()? onConnected;
  Function()? onDisconnected;

  // Getters
  WsStatus get status => _status;
  String? get url => _url;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == WsStatus.connected;
  Stream<WsMessage> get messageStream => _messageController.stream;
  Stream<WsStatus> get statusStream => _statusController.stream;

  /// 初始化，从本地存储加载 URL 并自动连接
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _url = prefs.getString('ws_url');
    if (_url != null && _url!.isNotEmpty) {
      logger.info('WebSocket', '发现已保存的地址: $_url，自动连接');
      await connect(_url!);
    }
  }

  /// 连接到 WebSocket 服务器
  Future<void> connect(String url) async {
    if (_status == WsStatus.connecting || _status == WsStatus.connected) {
      return;
    }

    // 取消旧的连接
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;

    _url = url;
    // 保存 URL 到本地
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ws_url', url);
    _status = WsStatus.connecting;
    _errorMessage = null;
    notifyListeners();
    _statusController.add(_status);

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
      _statusController.add(_status);

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
    _statusController.add(_status);

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

  /// 查询卡密状态
  Future<Map<String, dynamic>?> getKamiInfo(String kamiKey) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法查询卡密状态');
      return null;
    }

    final completer = Completer<Map<String, dynamic>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _kamiInfoRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          completer.complete(data);
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _kamiInfoRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'kami_info',
        'params': {
          'kamiKey': kamiKey,
        },
      },
      id: _kamiInfoRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  String? _loginRequestId;
  String? _kamiInfoRequestId;
  String? _getAppsRequestId;
  String? _getAppInfoRequestId;
  String? _getNextFileRequestId;
  String? _startScanRequestId;
  String? _readerTestRequestId;
  String? _getProcessesRequestId;
  String? _getModulesRequestId;
  String? _getFilesRequestId;
  String? _convertFormatRequestId;
  String? _previewConvertedRequestId;
  String? _debugPointersRequestId;
  String? _compareRequestId;
  String? _compareNormRequestId;
  String? _toOutRequestId;
  String? _checkFileExistsRequestId;
  String? _filterListTargetsRequestId;
  String? _filterRunRequestId;

  /// 获取运行中的应用列表（通过执行外部scan命令）
  Future<List<Map<String, dynamic>>?> getApps() async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法获取应用列表');
      return null;
    }

    final completer = Completer<List<Map<String, dynamic>>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _getAppsRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['apps'] != null) {
            final apps = (data['apps'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList();
            completer.complete(apps);
          } else {
            completer.complete([]);
          }
        } else {
          completer.complete([]);
        }
        subscription.cancel();
      }
    });

    _getAppsRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'get_apps',
      },
      id: _getAppsRequestId,
    ));

    // 超时处理（外部命令可能需要较长时间）
    Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 根据包名获取应用信息（包括PID）
  Future<Map<String, dynamic>?> getAppInfo(String packageName) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法获取应用信息');
      return null;
    }

    final completer = Completer<Map<String, dynamic>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _getAppInfoRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true) {
            completer.complete(data);
          } else {
            completer.complete(null);
          }
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _getAppInfoRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'get_app_info',
        'params': {
          'packageName': packageName,
        },
      },
      id: _getAppInfoRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 获取下一个可用的输出文件路径
  Future<String?> getNextFile(String dir, String extension) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法获取下一个文件路径');
      return null;
    }

    final completer = Completer<String?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _getNextFileRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['path'] != null) {
            completer.complete(data['path'] as String);
          } else {
            completer.complete(null);
          }
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _getNextFileRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'get_next_file',
        'params': {
          'dir': dir,
          'extension': extension,
        },
      },
      id: _getNextFileRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 读取器自测
  Future<String?> readerTest(String readerType) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法进行读取器测试');
      return null;
    }

    final completer = Completer<String?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _readerTestRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['output'] != null) {
            completer.complete(data['output'] as String);
          } else {
            completer.complete(null);
          }
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _readerTestRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'reader_test',
        'params': {
          'reader': readerType,
        },
      },
      id: _readerTestRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 启动扫描任务
  Future<String?> startScan({
    required String? packageName,
    required int? pid,
    required List<String> addresses,
    required int depth,
    required int offset,
    required String outputFile,
    required int count,
    required int size,
    required List<String> ranges,
    required bool brutalMode,
    required bool pageFault,
    required bool handleB4000000,
    String? reader,
    String? normFile,
    String? kamiKey,
  }) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法启动扫描');
      return null;
    }

    final completer = Completer<String?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _startScanRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['taskId'] != null) {
            completer.complete(data['taskId'] as String);
          } else {
            completer.complete(null);
          }
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _startScanRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    final params = {
      'addresses': addresses,
      'depth': depth,
      'offset': offset,
      'count': count,
      'size': size,
      'ranges': ranges,
      'pageFault': pageFault,
      'brutalMode': brutalMode,
      'handleB4000000': handleB4000000,
    };

    // 添加卡密参数
    if (kamiKey != null && kamiKey.isNotEmpty) {
      params['kamiKey'] = kamiKey;
    }

    // 根据数据格式选择输出参数
    // 通用格式(brutalMode=false): 使用 -f 参数 (outputFile)
    // 暴力格式(brutalMode=true): 使用 --norm 参数 (normFile)
    if (!brutalMode) {
      // 通用格式：输出文件
      params['outputFile'] = outputFile;
    } else {
      // 暴力格式：输出归一化文件
      if (normFile != null && normFile.isNotEmpty) {
        params['normFile'] = normFile;
      } else {
        // 如果没有指定normFile，使用outputFile路径但改为.norm扩展名
        final normPath = outputFile.replaceAll(RegExp(r'\.(out|bin)$'), '.norm');
        params['normFile'] = normPath;
      }
    }

    if (packageName != null) {
      params['packageName'] = packageName;
    } else if (pid != null) {
      params['pid'] = pid;
    }

    if (reader != null) {
      params['reader'] = reader;
    }

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'start_scan',
        'params': params,
      },
      id: _startScanRequestId,
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

  /// 获取进程列表
  Future<List<Map<String, dynamic>>?> getProcesses() async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法获取进程列表');
      return null;
    }

    final completer = Completer<List<Map<String, dynamic>>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _getProcessesRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['processes'] != null) {
            final processes = (data['processes'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList();
            completer.complete(processes);
          } else {
            completer.complete([]);
          }
        } else {
          completer.complete([]);
        }
        subscription.cancel();
      }
    });

    _getProcessesRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'get_processes',
      },
      id: _getProcessesRequestId,
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

  /// 获取模块列表
  Future<List<Map<String, dynamic>>?> getModules(String packageName) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法获取模块列表');
      return null;
    }

    final completer = Completer<List<Map<String, dynamic>>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _getModulesRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['modules'] != null) {
            final modules = (data['modules'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList();
            completer.complete(modules);
          } else {
            completer.complete([]);
          }
        } else {
          completer.complete([]);
        }
        subscription.cancel();
      }
    });

    _getModulesRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'get_modules',
        'params': {
          'packageName': packageName,
        },
      },
      id: _getModulesRequestId,
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

  /// 获取文件列表
  Future<List<Map<String, dynamic>>?> getFiles(String dir, List<String> extensions) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法获取文件列表');
      return null;
    }

    final completer = Completer<List<Map<String, dynamic>>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _getFilesRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['files'] != null) {
            final files = (data['files'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList();
            completer.complete(files);
          } else {
            completer.complete([]);
          }
        } else {
          completer.complete([]);
        }
        subscription.cancel();
      }
    });

    _getFilesRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'get_files',
        'params': {
          'dir': dir,
          'extensions': extensions,
        },
      },
      id: _getFilesRequestId,
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

  /// 转换格式文件（.out/.bin -> .txt）
  Future<String?> convertFormatFile({
    required String filePath,
    required int limit,
    required bool is32Bit,
    String? outputPath,
    bool folder = false,
    int? levelMin,
    int? levelMax,
    String? kamiKey,
  }) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法转换格式文件');
      return null;
    }

    final completer = Completer<String?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _convertFormatRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['taskId'] != null) {
            completer.complete(data['taskId'] as String);
          } else {
            completer.complete(null);
          }
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _convertFormatRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    final Map<String, dynamic> params = {
      'filePath': filePath,
      'limit': limit,
      'is32Bit': is32Bit,
      'folder': folder,
    };

    if (outputPath != null) {
      params['outputPath'] = outputPath;
    }
    if (levelMin != null) {
      params['levelMin'] = levelMin;
    }
    if (levelMax != null) {
      params['levelMax'] = levelMax;
    }

    // 添加卡密参数
    if (kamiKey != null && kamiKey.isNotEmpty) {
      params['kamiKey'] = kamiKey;
    }

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'convert_format',
        'params': params,
      },
      id: _convertFormatRequestId,
    ));

    // 超时处理（转换可能需要较长时间）
    Timer(const Duration(seconds: 60), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// norm 转 out（同步返回结果）
  Future<Map<String, dynamic>?> toOut({
    required List<String> inputFiles,
    String? outputFile,
    String? kamiKey,
  }) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法执行 norm 转 out');
      return null;
    }

    final completer = Completer<Map<String, dynamic>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _toOutRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          completer.complete(message.data as Map<String, dynamic>);
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _toOutRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    final Map<String, dynamic> params = {
      'inputFiles': inputFiles,
    };

    if (outputFile != null) {
      params['outputFile'] = outputFile;
    }

    // 添加卡密参数
    if (kamiKey != null && kamiKey.isNotEmpty) {
      params['kamiKey'] = kamiKey;
    }

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'to_out',
        'params': params,
      },
      id: _toOutRequestId,
    ));

    // 超时处理（10秒，因为是快速操作）
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 预览转换后的 txt 文件（前200行）
  Future<List<String>?> previewConvertedFile(String filePath) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法预览转换结果');
      return null;
    }

    final completer = Completer<List<String>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _previewConvertedRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['lines'] != null) {
            final lines = (data['lines'] as List)
                .map((e) => e.toString())
                .toList();
            completer.complete(lines);
          } else {
            completer.complete([]);
          }
        } else {
          completer.complete([]);
        }
        subscription.cancel();
      }
    });

    _previewConvertedRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'preview_txt',
        'params': {
          'filePath': filePath,
          'maxLines': 200,
        },
      },
      id: _previewConvertedRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 批量调试指针
  Future<List<Map<String, dynamic>>?> debugPointers(List<String> pointerChains) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法调试指针');
      return null;
    }

    final completer = Completer<List<Map<String, dynamic>>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _debugPointersRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['results'] != null) {
            final results = (data['results'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList();
            completer.complete(results);
          } else {
            completer.complete([]);
          }
        } else {
          completer.complete([]);
        }
        subscription.cancel();
      }
    });

    _debugPointersRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'debug_pointers',
        'params': {
          'pointers': pointerChains,
        },
      },
      id: _debugPointersRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 对比两个链文件（基础对比/极速对比）
  Future<String?> compareFiles({
    required List<String> inputFiles,
    String? outputFile,
    required String mode,  // text=基础对比, bin=极速对比
    required bool is32Bit,
    int? limit,
    int? levelMin,
    int? levelMax,
    String? kamiKey,
  }) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法执行对比');
      return null;
    }

    final completer = Completer<String?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _compareRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['taskId'] != null) {
            completer.complete(data['taskId'] as String);
          } else {
            completer.complete(null);
          }
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _compareRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    final Map<String, dynamic> params = {
      'inputFiles': inputFiles,
      'mode': mode,
      'bit': is32Bit ? 32 : 64,
    };

    if (outputFile != null) {
      params['outputFile'] = outputFile;
    }

    if (limit != null && limit > 0) {
      params['limit'] = limit;
    }

    if (levelMin != null) {
      params['levelMin'] = levelMin;
    }

    if (levelMax != null) {
      params['levelMax'] = levelMax;
    }

    // 添加卡密参数
    if (kamiKey != null && kamiKey.isNotEmpty) {
      params['kamiKey'] = kamiKey;
    }

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'compare',
        'params': params,
      },
      id: _compareRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 60), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 对比两个 .norm 文件（暴力对比）
  Future<String?> compareNormFiles({
    required List<String> inputFiles,
    String? outputFile,
    int? minLevel,
    int? maxLevel,
    String? kamiKey,
  }) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法执行暴力对比');
      return null;
    }

    final completer = Completer<String?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _compareNormRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['taskId'] != null) {
            completer.complete(data['taskId'] as String);
          } else {
            completer.complete(null);
          }
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _compareNormRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    final Map<String, dynamic> params = {
      'inputFiles': inputFiles,
    };

    if (outputFile != null) {
      params['outputFile'] = outputFile;
    }

    if (minLevel != null) {
      params['minLevel'] = minLevel;
    }

    if (maxLevel != null) {
      params['maxLevel'] = maxLevel;
    }

    // 添加卡密参数
    if (kamiKey != null && kamiKey.isNotEmpty) {
      params['kamiKey'] = kamiKey;
    }

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'compare_norm',
        'params': params,
      },
      id: _compareNormRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 60), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 检查文件是否存在
  Future<bool> checkFileExists(String filePath) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法检查文件');
      return false;
    }

    final completer = Completer<bool>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _checkFileExistsRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          completer.complete(data['exists'] == true);
        } else {
          completer.complete(false);
        }
        subscription.cancel();
      }
    });

    _checkFileExistsRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'check_file_exists',
        'params': {
          'path': filePath,
        },
      },
      id: _checkFileExistsRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete(false);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 列出过滤目标地址（对应 filter -l 命令）
  Future<Map<String, dynamic>?> filterListTargets({
    required String inputFile,
    required String mode, // bin 或 text
    required bool is32Bit,
    required int pid,
    int valueType = 0,
    String? reader,
    String? kamiKey,
  }) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法列出过滤目标');
      return null;
    }

    final completer = Completer<Map<String, dynamic>?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _filterListTargetsRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          completer.complete(data);
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _filterListTargetsRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    final params = {
      'input': inputFile,
      'mode': mode,
      'bit': is32Bit ? 32 : 64,
      'valueType': valueType,
      'pid': pid,
    };

    // 添加 reader 参数（如果指定）
    if (reader != null && reader.isNotEmpty) {
      params['reader'] = reader;
    }

    // 添加卡密参数
    if (kamiKey != null && kamiKey.isNotEmpty) {
      params['kamiKey'] = kamiKey;
    }

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'filter_list_targets',
        'params': params,
      },
      id: _filterListTargetsRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

  /// 执行过滤（对应 filter 命令）
  Future<String?> filterRun({
    required String inputFile,
    required String mode, // bin 或 text
    required bool is32Bit,
    required int targetAddress,
    required String outputFile,
    required int pid,
    required String outputMode, // bin 或 text
    String reader = '',
    String? kamiKey,
  }) async {
    if (!isConnected) {
      logger.warning('WebSocket', '未连接，无法执行过滤');
      return null;
    }

    final completer = Completer<String?>();

    // 监听响应
    late StreamSubscription subscription;
    subscription = messageStream.listen((message) {
      if (message.id == _filterRunRequestId) {
        if (message.type == WsMessageType.response && message.data != null) {
          final data = message.data as Map<String, dynamic>;
          if (data['success'] == true && data['taskId'] != null) {
            completer.complete(data['taskId'] as String);
          } else {
            completer.complete(null);
          }
        } else {
          completer.complete(null);
        }
        subscription.cancel();
      }
    });

    _filterRunRequestId = DateTime.now().millisecondsSinceEpoch.toString();

    final params = {
      'input': inputFile,
      'mode': mode,
      'bit': is32Bit ? 32 : 64,
      'target': targetAddress,
      'output': outputFile,
      'pid': pid,
      'outputMode': outputMode,
    };

    // 添加 reader 参数（如果指定）
    if (reader.isNotEmpty) {
      params['reader'] = reader;
    }

    // 添加卡密参数
    if (kamiKey != null && kamiKey.isNotEmpty) {
      params['kamiKey'] = kamiKey;
    }

    send(WsMessage(
      type: WsMessageType.command,
      data: {
        'command': 'filter_run',
        'params': params,
      },
      id: _filterRunRequestId,
    ));

    // 超时处理
    Timer(const Duration(seconds: 60), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription.cancel();
      }
    });

    return completer.future;
  }

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
    _statusController.add(_status);

    onError?.call(error);
    logger.error('WebSocket', '错误: $error');

    // 尝试重连
    _tryReconnect();
  }

  /// 处理断开连接
  void _handleDisconnected() {
    if (_status == WsStatus.connected) {
      // 先取消旧的subscription
      _subscription?.cancel();
      _subscription = null;

      _status = WsStatus.disconnected;
      notifyListeners();
      _statusController.add(_status);
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
    _statusController.add(_status);

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
    _statusController.close();
    super.dispose();
  }
}

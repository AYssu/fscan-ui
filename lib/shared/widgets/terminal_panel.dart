import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voo_terminal/voo_terminal.dart';
import 'package:fscan/core/network/ws_service.dart';
import 'package:fscan/core/utils/logger.dart';

/// 嵌入式终端面板
class TerminalPanel extends StatefulWidget {
  final String? taskId;

  const TerminalPanel({
    super.key,
    this.taskId,
  });

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  late TerminalController _terminalController;
  StreamSubscription? _subscription;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _terminalController = TerminalController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initStream();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _terminalController.dispose();
    super.dispose();
  }

  /// 初始化WebSocket流监听
  void _initStream() {
    final wsService = context.read<WsService>();
    _subscription = wsService.messageStream.listen((message) {
      // 只处理stream类型的消息
      if (message.type != WsMessageType.stream) {
        return;
      }

      // 检查是否是扫描输出消息
      if (message.data != null) {
        final data = message.data as Map<String, dynamic>;
        final taskId = data['taskId'] as String?;
        final type = data['type'] as String?;
        final line = data['line'] as String?;
        final messageText = data['message'] as String?;

        // 如果指定了taskId，只接收该任务的消息
        if (widget.taskId != null && taskId != widget.taskId) {
          return;
        }

        if (type == 'start') {
          setState(() => _isRunning = true);
          _terminalController.write(messageText ?? '任务开始');
        } else if (type == 'stdout' && line != null) {
          _terminalController.write(line);
        } else if (type == 'stderr' && line != null) {
          _terminalController.write(line);
        } else if (type == 'complete') {
          final success = data['success'] as bool? ?? false;
          setState(() => _isRunning = false);
          _terminalController.write(success ? '✓ 扫描完成' : '✗ 扫描失败');
        } else if (type == 'error') {
          setState(() => _isRunning = false);
          _terminalController.write(messageText ?? '未知错误');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: VooTerminal(
        controller: _terminalController,
        config: TerminalConfig.preview(),
        theme: VooTerminalTheme.classic().copyWith(
          backgroundColor: const Color(0xFF1E1E1E),
          textColor: Colors.white,
          scrollbarColor: Colors.white.withAlpha(100),
        ),
      ),
    );
  }
}

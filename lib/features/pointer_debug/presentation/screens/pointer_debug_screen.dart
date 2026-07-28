import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fscan/core/network/ws_service.dart';

/// 指针调试结果
class PointerDebugResult {
  final String input;
  final String? error;
  final String? dword;
  final String? floatValue;
  final List<String> traceSteps;

  PointerDebugResult({
    required this.input,
    this.error,
    this.dword,
    this.floatValue,
    this.traceSteps = const [],
  });

  factory PointerDebugResult.fromJson(Map<String, dynamic> json) {
    return PointerDebugResult(
      input: json['input'] ?? '',
      error: json['error'],
      dword: json['dword'],
      floatValue: json['float'],
      traceSteps: (json['trace'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

/// 指针批量调试页面
class PointerDebugScreen extends StatefulWidget {
  const PointerDebugScreen({super.key});

  @override
  State<PointerDebugScreen> createState() => _PointerDebugScreenState();
}

class _PointerDebugScreenState extends State<PointerDebugScreen> {
  final TextEditingController _inputController = TextEditingController();
  List<PointerDebugResult> results = [];
  bool _isDebugging = false;
  int _expandedIndex = -1;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  /// 获取输入的指针链列表
  List<String> _getInputLines() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return [];
    return text.split('\n').where((line) => line.trim().isNotEmpty).toList();
  }

  /// 开始调试
  Future<void> _startDebug() async {
    final lines = _getInputLines();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入指针链条')),
      );
      return;
    }

    if (lines.length > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多支持200条指针链条')),
      );
      return;
    }

    setState(() {
      _isDebugging = true;
      results = [];
      _expandedIndex = -1;
    });

    try {
      final wsService = context.read<WsService>();
      final debugResults = await wsService.debugPointers(lines);

      if (debugResults != null && mounted) {
        setState(() {
          results = debugResults.map((r) => PointerDebugResult.fromJson(r)).toList();
          _isDebugging = false;
        });
      } else if (mounted) {
        setState(() => _isDebugging = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('调试失败')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDebugging = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('调试失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('指针批量调试'),
        actions: [
          if (results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                setState(() {
                  results = [];
                  _expandedIndex = -1;
                });
              },
              tooltip: '清空结果',
            ),
        ],
      ),
      body: Column(
        children: [
          // 输入区域
          _buildInputArea(),

          // 结果列表
          Expanded(
            child: _buildResultList(),
          ),
        ],
      ),
    );
  }

  /// 输入区域
  Widget _buildInputArea() {
    final lineCount = _getInputLines().length;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('输入指针链条', style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  '$lineCount/200',
                  style: TextStyle(
                    fontSize: 12,
                    color: lineCount > 200
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '每行一条，格式: libUE4.so[Cd][1]+0xffff+0x123',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _inputController,
              maxLines: 8,
              maxLength: 200 * 50, // 估算200行
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'libUE4.so[Cd][1]+0xffff+0x123+0x234\nlibil2cpp.so[Cb][2]+0x100',
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(12),
              ),
              onChanged: (value) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isDebugging || lineCount == 0 ? null : _startDebug,
                icon: _isDebugging
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isDebugging ? '调试中...' : '开始调试 ($lineCount 条)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 结果列表
  Widget _buildResultList() {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              '暂无调试结果',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '输入指针链条后点击开始调试',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        final isExpanded = _expandedIndex == index;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: [
              // 结果头部（可点击展开）
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedIndex = isExpanded ? -1 : index;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 输入
                      Row(
                        children: [
                          Icon(
                            result.error != null ? Icons.error : Icons.check_circle,
                            size: 16,
                            color: result.error != null
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              result.input,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 最终结果
                      if (result.error != null)
                        Text(
                          '错误: ${result.error}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      else
                        Row(
                          children: [
                            _buildResultChip('dword', result.dword ?? '-'),
                            const SizedBox(width: 8),
                            _buildResultChip('float', result.floatValue ?? '-'),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              // 展开的详细路径
              if (isExpanded && result.traceSteps.isNotEmpty) ...[
                const Divider(height: 1),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '跳转路径',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...result.traceSteps.asMap().entries.map((entry) {
                        final stepIndex = entry.key;
                        final step = entry.value;
                        final isLast = stepIndex == result.traceSteps.length - 1;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 步骤编号
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: isLast
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.outline,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${stepIndex + 1}',
                                    style: const TextStyle(fontSize: 10, color: Colors.white),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 步骤内容
                              Expanded(
                                child: Text(
                                  step,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 结果标签
  Widget _buildResultChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

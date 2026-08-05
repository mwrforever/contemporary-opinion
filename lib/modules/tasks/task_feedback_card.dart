import 'package:flutter/material.dart';

import 'voice_input_screen.dart';

/// 语音规划结果反馈卡：一行摘要（已添加/冲突待处理/跳过），可手动关闭。
class TaskFeedbackCard extends StatelessWidget {
  const TaskFeedbackCard({super.key, required this.result, this.onDismiss});

  final VoicePlanResult result;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[
      '已添加 ${result.added} 条',
      if (result.conflict > 0) '${result.conflict} 条冲突待处理',
      if (result.skipped > 0) '跳过 ${result.skipped} 条',
    ];
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4, top: 6, bottom: 6),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                parts.join(' · '),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}

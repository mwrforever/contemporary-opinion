import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 空状态：友好的插画（纯形状绘制）+ 引导文案。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Illustration(color: scheme.primary),
            const SizedBox(height: 28),
            Text(
              '还没有安排',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点右下角 +，手动添加或语音录入都行。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  final Color color;

  const _Illustration({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.event_available_outlined, size: 64, color: color),
          Positioned(
            right: 26,
            bottom: 26,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

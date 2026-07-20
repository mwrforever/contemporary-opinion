import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 任务 Tab 的悬浮菜单（Speed Dial）：展开为「手动录入 / 语音录入」两项。
///
/// 跨模块复用的公开组件（原 [HomeScreen] 内的私有 `_SpeedDial` / `_DialItem`
/// 提升而来）。FAB 属于各 Tab 自身的 Scaffold，不放在壳层，以免跨模块误触。
///
/// 收起态为单个「+」，展开为「手动录入 / 语音录入」两项（手动在前）。
class SpeedDial extends StatelessWidget {
  /// 是否展开。
  final bool open;

  /// 切换展开/收起。
  final VoidCallback onToggle;

  /// 「手动录入」回调。
  final VoidCallback onAdd;

  /// 「语音录入」回调。
  final VoidCallback onVoice;

  const SpeedDial({
    super.key,
    required this.open,
    required this.onToggle,
    required this.onAdd,
    required this.onVoice,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !open,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                DialItem(
                    icon: Icons.edit_outlined, label: '手动录入', onTap: onAdd),
                const SizedBox(height: 12),
                DialItem(icon: Icons.mic, label: '语音录入', onTap: onVoice),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        FloatingActionButton(
          onPressed: onToggle,
          child: AnimatedRotation(
            turns: open ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            child: Icon(open ? Icons.close : Icons.add),
          ),
        ),
      ],
    );
  }
}

/// Speed Dial 的单项：发丝边框 + 圆角 + 扩散阴影（非辉光）。
class DialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const DialItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.1)),
          boxShadow: AppTheme.elevation(isDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 14, color: scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

/// 便捷包装：内部自持展开状态，对外仅暴露 [onAdd] / [onVoice]，
/// 让详情页无需改成 [StatefulWidget] 即可复用 [SpeedDial]。
class SpeedDialFab extends StatefulWidget {
  /// 「手动录入」回调。
  final VoidCallback onAdd;

  /// 「语音录入」回调。
  final VoidCallback onVoice;

  const SpeedDialFab({
    super.key,
    required this.onAdd,
    required this.onVoice,
  });

  @override
  State<SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<SpeedDialFab> {
  bool _open = false;

  void _run(VoidCallback action) {
    action();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) => SpeedDial(
        open: _open,
        onToggle: () => setState(() => _open = !_open),
        onAdd: () => _run(widget.onAdd),
        onVoice: () => _run(widget.onVoice),
      );
}

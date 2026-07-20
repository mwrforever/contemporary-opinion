import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 操作反馈类型：成功 / 删除 / 撤销，三态共用同一卡片。
enum FeedbackType {
  success,
  delete,
  undo,
}

/// 轻量操作反馈卡片。
///
/// 通过应用级 [Overlay] 浮层呈现，顶部居中，不阻塞页面交互。进入时淡入 + 上滑，
/// 停留 [duration]（默认 3s）后下滑淡出并自动移除。删除态可携带撤销动作
/// （[actionLabel] + [onAction]）。
///
/// 与既有 SnackBar 相比，它脱离 [ScaffoldMessenger]，避免被 IndexedStack 父级
/// 重建干扰，且在语音录入页 `pop` 回 [TasksTab] 后仍可稳定展示成功反馈。
class TaskFeedbackCard {
  TaskFeedbackCard._();

  /// 展示一条反馈卡片。
  ///
  /// [type] 决定语义色与图标；[message] 为展示文案；[actionLabel]/[onAction]
  /// 仅删除态使用（"撤销"）。[duration] 为停留时长，超时自动消失。
  ///
  /// 若 [context] 已卸载或不存在 [Overlay]，则安全忽略（不抛异常）。
  static void show(
    BuildContext context, {
    required FeedbackType type,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TaskFeedbackOverlay(
        type: type,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
        onDismissed: () {
          // 动画结束后移除自身；捕获可能的二次 remove。
          try {
            entry.remove();
          } catch (_) {
            // 已移除，忽略。
          }
        },
      ),
    );
    overlay.insert(entry);
  }
}

/// 反馈卡片的浮层实现：管理进入 / 停留 / 退出三段动画。
class _TaskFeedbackOverlay extends StatefulWidget {
  final FeedbackType type;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onDismissed;

  const _TaskFeedbackOverlay({
    required this.type,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_TaskFeedbackOverlay> createState() => _TaskFeedbackOverlayState();
}

class _TaskFeedbackOverlayState extends State<_TaskFeedbackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.3),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _ctrl.addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // 进入完成 → 停留 duration 后开始退出。
      Future.delayed(widget.duration, () {
        if (mounted) _ctrl.reverse();
      });
    } else if (status == AnimationStatus.dismissed) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _ctrl
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  ({Color bg, Color fg, IconData icon}) _style() {
    switch (widget.type) {
      case FeedbackType.success:
        return (bg: AppTheme.accent, fg: Colors.white, icon: Icons.check_circle_outline);
      case FeedbackType.delete:
        return (bg: AppTheme.danger, fg: Colors.white, icon: Icons.delete_outline);
      case FeedbackType.undo:
        return (bg: AppTheme.accent, fg: Colors.white, icon: Icons.undo_outlined);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _style();
    final hasAction = widget.actionLabel != null && widget.onAction != null;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: SafeArea(
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: _slide,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: style.bg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(style.icon, color: style.fg, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: style.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (hasAction) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          widget.onAction?.call();
                          // 点击撤销后立即退出。
                          if (mounted) _ctrl.reverse();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: style.fg,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(widget.actionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

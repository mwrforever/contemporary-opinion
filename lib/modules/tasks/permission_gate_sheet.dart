import 'package:flutter/material.dart';

/// 新建任务前的通知权限引导抽屉（底部弹层）。
///
/// 任务提醒依赖系统通知与精确闹钟权限；未授权时「手动新增 / 语音规划」先弹出
/// 本抽屉，用户点击「去开启」触发系统权限请求（[onRequest] 返回是否已授权）：
/// - 已授权 → 关闭抽屉并放行（pop(true)）；
/// - 仍未授权 → 抽屉内提示「仍未开启」，保持拦截不放行。
/// 「暂不开启」→ pop(false)，任务模块保持不可用。
///
/// 依赖 [onRequest] 注入权限请求动作，便于在 widget 测试中用替身替换
/// 系统权限弹窗。
class PermissionGateSheet extends StatefulWidget {
  const PermissionGateSheet({super.key, required this.onRequest});

  /// 请求通知权限并返回是否已授权（调用方负责 ensurePermissions + 复查状态）
  final Future<bool> Function() onRequest;

  @override
  State<PermissionGateSheet> createState() => _PermissionGateSheetState();
}

class _PermissionGateSheetState extends State<PermissionGateSheet> {
  /// 系统权限请求进行中（按钮显示加载态，防止重复点击）
  bool _requesting = false;

  /// 用户拒绝/系统未授予：抽屉内展示提示并保持拦截
  bool _denied = false;

  /// 执行权限请求：成功则关闭抽屉并放行，失败则原地提示。
  Future<void> _request() async {
    setState(() {
      _requesting = true;
      _denied = false;
    });
    final ok = await widget.onRequest();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _requesting = false;
      _denied = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 拖拽指示条
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 图标 + 标题 + 说明
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 28,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '开启提醒权限',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '新建任务需要通知权限才能准时提醒。\n开启后即可正常使用任务模块。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_denied) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 15, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '仍未开启通知权限，请在系统设置中允许通知后重试。',
                          style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              // 操作按钮：去开启 / 暂不开启
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _requesting ? null : _request,
                  child: _requesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('去开启'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: _requesting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('暂不开启'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

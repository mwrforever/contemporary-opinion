import 'package:flutter/material.dart';


/// 表单分区：主色竖条 + 标题 + 发丝分隔线，与首页分组头视觉语言一致。
///
/// 跨模块复用的公开组件（原 [AddTaskScreen] 内的私有 `_Section` 提升而来）。
class Section extends StatelessWidget {
  /// 分区标题。
  final String title;

  /// 分区内的子组件（输入控件等）。
  final List<Widget> children;

  const Section({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16, top: 4),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Divider(
                  color: scheme.onSurface.withValues(alpha: 0.08),
                  thickness: 1,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        ...children,
        const SizedBox(height: 28),
      ],
    );
  }
}

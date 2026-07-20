import 'package:flutter/material.dart';


/// 字段标签：位于输入框「上方」，与输入控件保持 `spaceMd` 下间距。
///
/// 跨模块复用的公开组件（原 [AddTaskScreen] 内的私有 `_FieldLabel` 提升而来）。
class FieldLabel extends StatelessWidget {
  /// 标签文案。
  final String text;

  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

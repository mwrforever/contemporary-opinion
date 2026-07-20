import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 通用确认弹窗：破坏性操作前的二次确认。
///
/// 统一使用 [AlertDialog]，确认按钮固定为 [AppTheme.danger]（破坏性语义），
/// 取消为中性 [TextButton]。所有"清空 / 删除"类操作都应走本组件，避免重复造弹窗。
class ConfirmDialog {
  const ConfirmDialog._();

  /// 弹出确认框，返回用户选择：确认 `true`、取消或点遮罩 `false`。
  ///
  /// - [title] 标题文案。
  /// - [content] 说明文案，需讲清后果（如"不可撤销"）。
  /// - [confirmText] 确认按钮文字（如"清空""删除"）。
  static Future<bool> show(
    BuildContext context,
    String title,
    String content,
    String confirmText,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../../../../widgets/confirm_dialog.dart';

/// 购物车新建/编辑底部抽屉。
///
/// 新建时标题默认当天 yyyy年MM月dd日；点日历图标唤起日期选择器，选中后标题
/// 联动为该日期；编辑态底部追加「删除购物车」危险按钮（删除前二次确认，
/// 其下购物项由外键 SET NULL 回收为未分组）。保存/关闭后不 pop 外层页面，
/// 由列表/子页监听 store 自动刷新。
Future<void> showShoppingCartSheet(
  BuildContext context, {
  required NotebookStore store,
  NotebookShoppingCart? cart,
}) async {
  final created = cart ??
      NotebookShoppingCart(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: defaultCartTitle(DateTime.now()),
        createdAt: DateTime.now(),
      );
  final controller = TextEditingController(text: created.name);
  final noteController = TextEditingController(text: created.note ?? '');

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cart == null ? '新建购物车' : '编辑购物车',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTitleField(ctx, controller),
          const SizedBox(height: 8),
          TextField(
            controller: noteController,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              hintText: '如：楼下超市 · 手机支付',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final updated = NotebookShoppingCart(
                id: created.id,
                name: name,
                note: noteController.text.trim().isEmpty
                    ? null
                    : noteController.text.trim(),
                createdAt: created.createdAt,
              );
              if (cart == null) {
                store.addCart(updated);
              } else {
                store.updateCart(updated);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
          if (cart != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async {
                final ok = await ConfirmDialog.show(
                  ctx,
                  '删除购物车',
                  '删除「${cart.name}」，其下购物项将回收为未分组',
                  '删除',
                );
                if (ok) {
                  await store.deleteCart(cart.id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('删除购物车'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 标题字段：文本框 + 日历图标（日期选择器联动标题）。
Widget _buildTitleField(
    BuildContext context, TextEditingController controller) {
  return TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: '标题',
      suffixIcon: IconButton(
        icon: const Icon(Icons.calendar_today_outlined),
        tooltip: '选日期',
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
          );
          if (picked != null) {
            controller.text = defaultCartTitle(picked);
          }
        },
      ),
    ),
  );
}

/// 购物车默认标题：yyyy年MM月dd日。
String defaultCartTitle(DateTime d) => DateFormat('yyyy年MM月dd日').format(d);

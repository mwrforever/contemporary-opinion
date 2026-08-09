import 'package:flutter/material.dart';

import '../../../models/dictionary.dart';
import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../../../../widgets/confirm_dialog.dart';
import '../widgets/enum_chips_field.dart';
import '../widgets/notebook_shared.dart';

/// 购物项新建/编辑底部抽屉：物品名 + 实付金额 + 类型枚举（折叠）+ 日期选择器 + 备注。
///
/// 金额非法（空/负数）时就近提示不保存；编辑态底部追加「删除」。
Future<void> showShoppingItemSheet(
  BuildContext context, {
  required NotebookStore store,
  required String cartId,
  NotebookShopping? item,
}) async {
  final nameCtrl = TextEditingController(text: item?.item ?? '');
  final priceCtrl =
      TextEditingController(text: item == null ? '' : _trimPrice(item.price));
  final noteCtrl = TextEditingController(text: item?.note ?? '');
  var category = item?.category ?? '其他';
  var date = item?.date ?? '';
  String? error;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 26,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    item == null ? '添加购物项' : '编辑购物项',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                autocorrect: false,
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '物品名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                autocorrect: false,
                controller: priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '实付金额',
                  prefixText: '¥ ',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 12),
              Text('类型', style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 8),
              EnumChipsField(
                values: kShoppingItemTypes,
                selected: category,
                onChanged: (v) => setSheetState(() => category = v),
              ),
              const SizedBox(height: 12),
              DateField(
                label: '日期（可选）',
                value: date,
                onChanged: (v) => setSheetState(() => date = v),
              ),
              const SizedBox(height: 12),
              TextField(
                autocorrect: false,
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '如：超市买的 · 已付现金',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final price = num.tryParse(priceCtrl.text.trim());
                  if (name.isEmpty) {
                    setSheetState(() => error = '请输入物品名称');
                    return;
                  }
                  if (price == null || price < 0) {
                    setSheetState(() => error = '请输入有效金额（不小于 0）');
                    return;
                  }
                  final entity = NotebookShopping(
                    id: item?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    item: name,
                    price: price,
                    category: category,
                    note: noteCtrl.text.trim(),
                    cartId: cartId,
                    date: date,
                    createdAt: item?.createdAt ?? DateTime.now(),
                  );
                  if (item == null) {
                    store.addShopping(entity);
                  } else {
                    store.updateShopping(entity);
                  }
                  Navigator.of(ctx).pop();
                },
                child: const Text('保存'),
              ),
              if (item != null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    final ok = await ConfirmDialog.show(
                      ctx,
                      '删除购物项',
                      '删除「${item.item}」？',
                      '删除',
                    );
                    if (ok) {
                      await store.deleteShopping(item.id);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  child: const Text('删除'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// 金额回填：整数不带小数点，小数保留两位。
String _trimPrice(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

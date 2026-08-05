import 'package:flutter/material.dart';

import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../../../widgets/confirm_dialog.dart';
import '../widgets/notebook_report.dart';

/// 购物清单页：子购物车分组 + 购物项，聚合项数/预期/实付/差额。
class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key, required this.store});

  final NotebookStore store;

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addCart() async {
    final name = await _promptText('新建购物车', '名称', '');
    if (name == null || name.isEmpty || !mounted) return;
    await widget.store.addCart(
      NotebookShoppingCart(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        note: null,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _addItem(String cartId) async {
    final result = await _promptItem(
      title: '添加购物项',
      initial: null,
    );
    if (result == null || !mounted) return;
    await widget.store.addShopping(
      NotebookShopping(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        item: result.$1,
        expectedPrice: result.$2,
        actualPrice: result.$3,
        category: result.$4,
        note: '',
        cartId: cartId,
        date: '',
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _editItem(NotebookShopping item) async {
    final result = await _promptItem(
      title: '编辑购物项',
      initial: item,
    );
    if (result == null || !mounted) return;
    await widget.store.updateShopping(
      NotebookShopping(
        id: item.id,
        item: result.$1,
        expectedPrice: result.$2,
        actualPrice: result.$3,
        category: result.$4,
        note: item.note,
        cartId: item.cartId,
        date: item.date,
        createdAt: item.createdAt,
      ),
    );
  }

  Future<void> _deleteItem(NotebookShopping item) async {
    final ok = await ConfirmDialog.show(
      context,
      '删除购物项',
      '删除「${item.item}」？',
      '删除',
    );
    if (ok) await widget.store.deleteShopping(item.id);
  }

  Future<void> _deleteCart(NotebookShoppingCart cart) async {
    final ok = await ConfirmDialog.show(
      context,
      '删除购物车',
      '删除「${cart.name}」，其下购物项将回收为未分组',
      '删除',
    );
    if (ok) await widget.store.deleteCart(cart.id);
  }

  Future<String?> _promptText(String title, String label, String initial) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return value;
  }

  Future<(String, num, num, String)?> _promptItem({
    required String title,
    required NotebookShopping? initial,
  }) async {
    final name = TextEditingController(text: initial?.item ?? '');
    final expected = TextEditingController(text: initial?.expectedPrice.toString() ?? '');
    final actual = TextEditingController(text: initial?.actualPrice.toString() ?? '');
    final category = TextEditingController(text: initial?.category ?? '');
    final result = await showDialog<(String, num, num, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: '物品')),
              TextField(
                controller: expected,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '预期价'),
              ),
              TextField(
                controller: actual,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '实付'),
              ),
              TextField(controller: category, decoration: const InputDecoration(labelText: '分类')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop((
              name.text.trim(),
              num.tryParse(expected.text) ?? 0,
              num.tryParse(actual.text) ?? 0,
              category.text.trim(),
            )),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('购物清单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '消费趋势',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReportScreen(
                  title: '购物消费趋势',
                  unit: '¥',
                  data: [
                    for (final i in widget.store.shopping)
                      ReportDatum(date: i.date, value: i.actualPrice),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCart,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final cart in widget.store.shoppingCarts) ...[
            _cartHeader(cart),
            for (final item in widget.store.cartsOf(cart.id)) _itemTile(item),
            const Divider(),
          ],
          if (widget.store.shopping.any((i) => i.cartId.isEmpty)) ...[
            Text(
              '未分组',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final item in widget.store.shopping.where((i) => i.cartId.isEmpty))
              _itemTile(item),
          ],
          if (widget.store.shopping.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('还没有购物项，点右下角新建购物车')))
          else
            const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _cartHeader(NotebookShoppingCart cart) {
    final items = widget.store.cartsOf(cart.id);
    final expected = items.fold<num>(0, (s, i) => s + i.expectedPrice);
    final actual = items.fold<num>(0, (s, i) => s + i.actualPrice);
    final diff = expected - actual;
    return ListTile(
      title: Text(cart.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${items.length} 项 · 预期 ¥$expected · 实付 ¥$actual · 差 ¥$diff'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _addItem(cart.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteCart(cart),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(NotebookShopping item) {
    return ListTile(
      title: Text(item.item),
      subtitle: Text('预期 ¥${item.expectedPrice} · 实付 ¥${item.actualPrice}'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _deleteItem(item),
      ),
      onTap: () => _editItem(item),
    );
  }
}

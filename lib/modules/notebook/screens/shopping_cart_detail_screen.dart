import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../widgets/notebook_shared.dart';
import '../widgets/shopping_cart_sheet.dart';
import '../widgets/shopping_item_sheet.dart';

/// 子购物车子页：返回 + 车名 + 编辑入口 + 汇总卡 + 购物项列表。
///
/// 购物车可能被编辑（名称变化）或删除，故本页监听 store，按 [cartId]
/// 实时取最新车；车被删除时自动回退到列表。
class ShoppingCartDetailScreen extends StatefulWidget {
  final NotebookStore store;
  final String cartId;

  const ShoppingCartDetailScreen({
    super.key,
    required this.store,
    required this.cartId,
  });

  @override
  State<ShoppingCartDetailScreen> createState() =>
      _ShoppingCartDetailScreenState();
}

class _ShoppingCartDetailScreenState extends State<ShoppingCartDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => mounted ? setState(() {}) : null;

  @override
  Widget build(BuildContext context) {
    final carts =
        widget.store.shoppingCarts.where((c) => c.id == widget.cartId).toList();
    if (carts.isEmpty) {
      // 购物车已被删除：回退到列表
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }
    final cart = carts.first;
    final items = widget.store.cartsOf(cart.id);
    final total = items.fold<num>(0, (s, i) => s + i.price);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: Text(cart.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑购物车',
            onPressed: () =>
                showShoppingCartSheet(context, store: widget.store, cart: cart),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showShoppingItemSheet(
            context, store: widget.store, cartId: cart.id),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(context, total, items.length, cart.createdAt),
          const SizedBox(height: 18),
          Text('购物项（${items.length}）',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final it in items) _itemTile(context, it),
          if (items.isEmpty)
            const NotebookEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: '这个购物车还没有条目',
              subtitle: '点右下角 + 添加购物项',
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(
      BuildContext context, num total, int count, DateTime createdAt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Text(formatYuan(total),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const Spacer(),
          _sumItem('$count', '条目'),
          const SizedBox(width: 18),
          _sumItem(DateFormat('M月d日').format(createdAt), '创建'),
        ],
      ),
    );
  }

  Widget _sumItem(String v, String k) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(v,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(k,
              style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _itemTile(BuildContext context, NotebookShopping it) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.shopping_bag_outlined, size: 20),
        ),
        title: Text(it.item, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${it.category.isEmpty ? '未分类' : it.category} · '
          '${it.date.isEmpty ? '未记录日期' : it.date}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(formatYuan(it.price),
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        onTap: () => showShoppingItemSheet(
            context, store: widget.store, cartId: it.cartId, item: it),
      ),
    );
  }
}

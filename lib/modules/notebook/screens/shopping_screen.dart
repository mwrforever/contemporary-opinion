import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../widgets/notebook_shared.dart';
import '../widgets/shopping_cart_sheet.dart';
import 'shopping_cart_detail_screen.dart';
import 'shopping_trend_screen.dart';

/// 购物清单列表页：子购物车单行记录（标题 + 实付/条目数/创建时间）。
///
/// 点车行进子页查看购物项；右下 FAB 新建购物车（标题默认当天日期）；
/// 右上角为消费趋势报表入口；删除购物车后回收的项落在底部「未分组」行。
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
    widget.store.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final carts = [...widget.store.shoppingCarts]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final ungrouped =
        widget.store.shopping.where((i) => i.cartId.isEmpty).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('购物清单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insert_chart_outlined),
            tooltip: '消费趋势',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ShoppingTrendScreen(store: widget.store),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showShoppingCartSheet(context, store: widget.store),
        child: const Icon(Icons.add),
      ),
      body: carts.isEmpty && ungrouped.isEmpty
          ? const NotebookEmptyState(
              icon: Icons.shopping_cart_outlined,
              title: '还没有购物车',
              subtitle: '点右下角新建购物车，标题默认当天日期',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final cart in carts)
                  _cartRow(context, cart, widget.store.cartsOf(cart.id)),
                if (ungrouped.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _ungroupedPseudoRow(context, ungrouped),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '删除购物车后，其下购物项自动回收至此「未分组」',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  /// 车行：图标 + 单行标题 + 单行元信息（实付/条目/创建时间）+ chevron。
  Widget _cartRow(BuildContext context, NotebookShoppingCart cart,
      List<NotebookShopping> items) {
    final total = items.fold<num>(0, (s, i) => s + i.price);
    final metaTime =
        cart.id.isEmpty ? '零散记录' : DateFormat('M月d日').format(cart.createdAt);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShoppingCartDetailScreen(
            store: widget.store,
            cartId: cart.id,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cart.id.isEmpty
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              cart.id.isEmpty
                  ? Icons.folder_outlined
                  : Icons.shopping_bag_outlined,
              size: 20,
              color: cart.id.isEmpty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 11),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cart.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '实付 ${formatYuan(total)} · ${items.length} 项 · $metaTime',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  /// 未分组伪车行：items 为未分组购物项。
  Widget _ungroupedPseudoRow(
      BuildContext context, List<NotebookShopping> ungrouped) {
    return _cartRow(
      context,
      NotebookShoppingCart(
        id: '',
        name: '未分组',
        createdAt: DateTime(2000),
        note: null,
      ),
      ungrouped,
    );
  }
}

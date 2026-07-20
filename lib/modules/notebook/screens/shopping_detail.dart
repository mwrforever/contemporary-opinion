import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/notebook_shopping.dart';
import '../../../services/aliyun_asr_service.dart';
import '../../../services/notebook_store.dart';
import '../../../services/notebook_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/speed_dial.dart';
import '../widgets/notebook_report.dart';
import '../widgets/notebook_shared.dart';

/// 新建子购物车的默认标题：按「年月日」格式（如 2026年07月20日）。
String _defaultCartTitle() {
  final n = DateTime.now();
  final m = n.month.toString().padLeft(2, '0');
  final d = n.day.toString().padLeft(2, '0');
  return '${n.year}年$m月$d日';
}

/// 购物清单详情：子购物车分组 + 列表；新建子购物车在右上角，手动/语音录入内置到子购物车内部。
class ShoppingDetail extends StatelessWidget {
  final AliyunAsrService asr;
  final NotebookVoiceService voice;

  const ShoppingDetail({
    super.key,
    required this.asr,
    required this.voice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('购物清单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: '报表',
            onPressed: () => _showReport(context),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建子购物车',
            onPressed: () => _showCartEdit(context),
          ),
        ],
      ),
      body: Consumer<NotebookStore>(
        builder: (context, store, _) {
          final all = store.shopping;
          final carts = store.shoppingCarts;
          final ungrouped = store.cartsOf(kDefaultCartId);
          if (all.isEmpty && carts.isEmpty) {
            return const NotebookEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: '还没有购物清单',
              subtitle: '点右上角「新建子购物车」，进入后在内部添加购物项或用语音记录。',
            );
          }
          final rows = <Widget>[];
          if (ungrouped.isNotEmpty) {
            rows.add(_CartRow(
              cartId: kDefaultCartId,
              name: kDefaultCartName,
              items: ungrouped,
              onTap: () => _openCart(context, store, kDefaultCartId, kDefaultCartName),
            ));
          }
          for (final c in carts) {
            final items = store.cartsOf(c.id);
            rows.add(_CartRow(
              cartId: c.id,
              name: c.name,
              items: items,
              createdAt: c.createdAt,
              onTap: () => _openCart(context, store, c.id, c.name,
                  createdAt: c.createdAt),
              onEdit: () => _showCartEdit(context, cart: c),
              onDelete: () => _deleteCart(context, c),
            ));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spaceSm),
            itemBuilder: (context, i) => rows[i],
          );
        },
      ),
    );
  }

  void _showReport(BuildContext context) {
    final store = context.read<NotebookStore>();
    final data = store.shopping.map((e) => ReportDatum(
          date: e.date.isEmpty
              ? DateFormat('yyyy-MM-dd').format(DateTime.now())
              : e.date,
          value: e.actualPrice != 0 ? e.actualPrice : e.expectedPrice,
        )).toList();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReportScreen(
        data: data,
        unit: '¥',
        title: '购物消费报表',
      ),
    ));
  }

  void _showCartEdit(BuildContext context, {NotebookShoppingCart? cart}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _CartEditSheet(
        cart: cart,
        onSave: (c) {
          final store = context.read<NotebookStore>();
          if (cart == null) {
            store.addCart(c);
          } else {
            store.updateCart(c);
          }
        },
        onDelete: cart == null
            ? null
            : () {
                final store = context.read<NotebookStore>();
                store.deleteCart(cart.id);
              },
      ),
    );
  }

  void _openCart(
    BuildContext context,
    NotebookStore store,
    String cartId,
    String name, {
    DateTime? createdAt,
  }) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _CartDetailScreen(
        cartId: cartId,
        name: name,
        createdAt: createdAt,
        asr: asr,
        voice: voice,
      ),
    ));
  }

  void _deleteCart(BuildContext context, NotebookShoppingCart cart) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除子购物车'),
            content: Text('确定删除「${cart.name}」？该购物车下的购物项会归入「未分组」。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('删除')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final store = context.read<NotebookStore>();
    // 购物项回收到「未分组」，避免成为不可见孤儿
    for (final it in store.cartsOf(cart.id)) {
      store.addShopping(NotebookShopping(
        id: it.id,
        item: it.item,
        expectedPrice: it.expectedPrice,
        actualPrice: it.actualPrice,
        category: it.category,
        note: it.note,
        cartId: kDefaultCartId,
        date: it.date,
        createdAt: it.createdAt,
      ));
    }
    store.deleteCart(cart.id);
  }
}

class _Preview extends StatelessWidget {
  final NotebookShopping item;
  const _Preview({required this.item});

  @override
  Widget build(BuildContext context) {
    final price = item.expectedPrice > 0
        ? '约 ¥${item.expectedPrice}'
        : (item.actualPrice > 0 ? '实付 ¥${item.actualPrice}' : '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.item, style: Theme.of(context).textTheme.titleMedium),
        if (price.isNotEmpty)
          Text(price,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppTheme.accent)),
        const SizedBox(height: 2),
        Text('创建于 ${DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4))),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final NotebookShopping item;
  final VoidCallback onDelete;

  const _Row({required this.item, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final price = item.expectedPrice > 0
        ? '约 ¥${item.expectedPrice}'
        : (item.actualPrice > 0 ? '实付 ¥${item.actualPrice}' : '');
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: ListTile(
        title: Text(item.item, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (price.isNotEmpty)
              Text(price,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppTheme.accent)),
            if (item.category.isNotEmpty)
              Text(item.category,
                  style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
            Text('创建于 ${DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.4))),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded,
              color: scheme.onSurface.withValues(alpha: 0.4)),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _CartStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _CartStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 2),
          Text(value,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color ?? scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  )),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  final String cartId;
  final String name;
  final List<NotebookShopping> items;
  final DateTime? createdAt;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CartRow({
    required this.cartId,
    required this.name,
    required this.items,
    this.createdAt,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expected = items.fold<num>(0, (s, e) => s + e.expectedPrice);
    final actual = items.fold<num>(0, (s, e) => s + e.actualPrice);
    final diff = actual - expected;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spaceSm),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NotebookChip(
                    label: name,
                    bg: AppTheme.accentSoft,
                    fg: AppTheme.accentStrong,
                  ),
                  const Spacer(),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: scheme.onSurface.withValues(alpha: 0.4),
                      onPressed: onEdit,
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      color: scheme.onSurface.withValues(alpha: 0.4),
                      onPressed: onDelete,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _CartStat(label: '项数', value: '${items.length}'),
                  _CartStat(
                      label: '预期', value: '¥$expected', color: AppTheme.accent),
                  _CartStat(
                      label: '实付', value: '¥$actual', color: AppTheme.accent),
                  _CartStat(
                      label: '差额',
                      value: '¥$diff',
                      color: diff >= 0 ? AppTheme.ok : AppTheme.danger),
                ],
              ),
              const SizedBox(height: 8),
              if (createdAt != null)
                Text(
                    '创建于 ${DateFormat('yyyy-MM-dd HH:mm').format(createdAt!)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.4))),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartDetailScreen extends StatelessWidget {
  final String cartId;
  final String name;
  final DateTime? createdAt;
  final AliyunAsrService asr;
  final NotebookVoiceService voice;
  const _CartDetailScreen({
    required this.cartId,
    required this.name,
    this.createdAt,
    required this.asr,
    required this.voice,
  });

  void _showAdd(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _ShoppingAddSheet(
        lockedCartId: cartId,
        onSave: (item) => context.read<NotebookStore>().addShopping(item),
      ),
    );
  }

  void _startVoice(BuildContext context) {
    showNotebookVoiceSheet<NotebookShopping>(
      context,
      NotebookVoiceSheet<NotebookShopping>(
        asr: asr,
        title: '语音录入购物清单',
        parse: voice.parseShopping,
        itemBuilder: (item) => _Preview(item: item),
        onConfirmed: (items) {
          final store = context.read<NotebookStore>();
          for (final it in items) store.addShopping(it);
        },
      ),
    );
  }

  void _editCart(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _CartEditSheet(
        cart: NotebookShoppingCart(id: cartId, name: name, createdAt: createdAt ?? DateTime.now()),
        onSave: (c) => context.read<NotebookStore>().updateCart(c),
        onDelete: null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑购物车',
            onPressed: () => _editCart(context),
          ),
        ],
        bottom: createdAt != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '创建于 ${DateFormat('yyyy-MM-dd HH:mm').format(createdAt!)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5)),
                  ),
                ),
              )
            : null,
      ),
      body: Consumer<NotebookStore>(
        builder: (context, store, _) {
          final items = store.cartsOf(cartId);
          if (items.isEmpty) {
            return const NotebookEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: '这个购物车还是空的',
              subtitle: '点下方按钮添加购物项，直接归入本购物车。',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spaceSm),
            itemBuilder: (context, i) {
              final it = items[i];
              return _Row(
                item: it,
                onDelete: () => store.deleteShopping(it.id),
              );
            },
          );
        },
      ),
      floatingActionButton: SpeedDialFab(
        onAdd: () => _showAdd(context),
        onVoice: () => _startVoice(context),
      ),
    );
  }
}

class _ShoppingAddSheet extends StatefulWidget {
  final void Function(NotebookShopping) onSave;
  final String initialCartId;
  /// 非空时表示「从某子购物车内部打开」，此时锁定归属、隐藏子购物车选择器。
  final String? lockedCartId;
  const _ShoppingAddSheet(
      {required this.onSave,
      this.initialCartId = kDefaultCartId,
      this.lockedCartId});

  @override
  State<_ShoppingAddSheet> createState() => _ShoppingAddSheetState();
}

class _ShoppingAddSheetState extends State<_ShoppingAddSheet> {
  final _item = TextEditingController();
  final _expected = TextEditingController();
  final _actual = TextEditingController();
  final _category = TextEditingController();
  final _note = TextEditingController();
  String _cartId = kDefaultCartId;

  @override
  void initState() {
    super.initState();
    _cartId = widget.lockedCartId ?? widget.initialCartId;
  }

  @override
  void dispose() {
    _item.dispose();
    _expected.dispose();
    _actual.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final item = _item.text.trim();
    if (item.isEmpty) return;
    widget.onSave(NotebookShopping(
      id: notebookNewId(),
      item: item,
      expectedPrice: num.tryParse(_expected.text) ?? 0,
      actualPrice: num.tryParse(_actual.text) ?? 0,
      category: _category.text.trim(),
      note: _note.text.trim(),
      cartId: _cartId,
      createdAt: DateTime.now(),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotebookStore>();
    final chips = <Widget>[
      ChoiceChip(
        label: const Text(kDefaultCartName),
        selected: _cartId == kDefaultCartId,
        onSelected: (_) => setState(() => _cartId = kDefaultCartId),
      ),
    ];
    for (final c in store.shoppingCarts) {
      chips.add(ChoiceChip(
        label: Text(c.name),
        selected: _cartId == c.id,
        onSelected: (_) => setState(() => _cartId = c.id),
      ));
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spaceLg,
          right: AppTheme.spaceLg,
          top: AppTheme.spaceLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spaceLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('添加购物项',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabeledField(
                        label: '物品 *', controller: _item, hint: '如 牛奶'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: LabeledField(
                                label: '预期价',
                                controller: _expected,
                                hint: '0',
                                keyboardType: TextInputType.number)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: LabeledField(
                                label: '实际价',
                                controller: _actual,
                                hint: '0',
                                keyboardType: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (widget.lockedCartId != null)
                      // 从子购物车内部打开：归属已锁定为当前购物车，仅展示只读提示。
                      Builder(builder: (ctx) {
                        final store = ctx.watch<NotebookStore>();
                        final lockedName = widget.lockedCartId == kDefaultCartId
                            ? kDefaultCartName
                            : store.shoppingCarts
                                    .where((c) => c.id == widget.lockedCartId)
                                    .firstOrNull
                                    ?.name ??
                                kDefaultCartName;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.05),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMd),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 16,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.45)),
                              const SizedBox(width: 8),
                              Text('归入：',
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.6))),
                              NotebookChip(
                                label: lockedName,
                                bg: AppTheme.accentSoft,
                                fg: AppTheme.accentStrong,
                              ),
                            ],
                          ),
                        );
                      })
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('子购物车',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7))),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: chips),
                        ],
                      ),
                    const SizedBox(height: 12),
                    LabeledField(
                        label: '分类',
                        controller: _category,
                        hint: '生鲜/日用'),
                    const SizedBox(height: 12),
                    LabeledField(label: '备注', controller: _note, maxLines: 2),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      onPressed: _save, child: const Text('保存')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartEditSheet extends StatefulWidget {
  final NotebookShoppingCart? cart;
  final void Function(NotebookShoppingCart) onSave;
  final VoidCallback? onDelete;
  const _CartEditSheet(
      {this.cart, required this.onSave, this.onDelete});

  @override
  State<_CartEditSheet> createState() => _CartEditSheetState();
}

class _CartEditSheetState extends State<_CartEditSheet> {
  final _name = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 新建子购物车时，名称默认填入「年月日」，用户可沿用或改写
    _name.text = widget.cart?.name ?? _defaultCartTitle();
    _note.text = widget.cart?.note ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _name.text.trim();
    final name = raw.isEmpty ? _defaultCartTitle() : raw;
    final existing = widget.cart;
    final cart = NotebookShoppingCart(
      id: existing?.id ?? notebookNewId(),
      name: name,
      createdAt: existing?.createdAt ?? DateTime.now(),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    widget.onSave(cart);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppTheme.spaceLg,
        right: AppTheme.spaceLg,
        top: AppTheme.spaceLg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.cart == null ? '新建子购物车' : '编辑子购物车',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          LabeledField(label: '名称 *', controller: _name, hint: '如 生鲜'),
          const SizedBox(height: 12),
          LabeledField(label: '备注', controller: _note, maxLines: 2),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('保存')),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                widget.onDelete!();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除'),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/notebook_store.dart';
import 'screens/ledger_screen.dart';
import 'screens/reading_screen.dart';
import 'screens/recipe_screen.dart';
import 'screens/shopping_screen.dart';
import 'screens/study_screen.dart';
import 'screens/trip_screen.dart';

/// 记事本 Tab：2 列网格六子功能入口（设计稿方向 A），格内显示条目数。
class NotebookTab extends StatefulWidget {
  const NotebookTab({super.key, required this.store});

  final NotebookStore store;

  @override
  State<NotebookTab> createState() => _NotebookTabState();
}

class _NotebookTabState extends State<NotebookTab> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    // 加载 SQLite 记事本数据；失败静默，空态兜底
    unawaited(_safe(widget.store.init()));
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _safe(Future<void> future) async {
    try {
      await future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final items = <_HubItem>[
      _HubItem(
        keyName: 'shopping',
        title: '购物清单',
        icon: Icons.shopping_bag_outlined,
        tint: Theme.of(context).colorScheme.primaryContainer,
        count: '${store.shopping.length} 项',
        screen: ShoppingScreen(store: store),
      ),
      _HubItem(
        keyName: 'ledger',
        title: '收支账本',
        icon: Icons.account_balance_wallet_outlined,
        tint: Theme.of(context).colorScheme.secondaryContainer,
        count: '${store.ledger.length} 笔',
        screen: LedgerScreen(store: store),
      ),
      _HubItem(
        keyName: 'reading',
        title: '读书清单',
        icon: Icons.menu_book_outlined,
        tint: Theme.of(context).colorScheme.tertiaryContainer,
        count: '${store.reading.length} 本',
        screen: ReadingScreen(store: store),
      ),
      _HubItem(
        keyName: 'trip',
        title: '旅游行程',
        icon: Icons.flight_takeoff_outlined,
        tint: Theme.of(context).colorScheme.primaryContainer,
        count: '${store.trips.length} 段',
        screen: TripScreen(store: store),
      ),
      _HubItem(
        keyName: 'study',
        title: '学习记录',
        icon: Icons.school_outlined,
        tint: Theme.of(context).colorScheme.secondaryContainer,
        count: '${store.courses.length} 门',
        screen: StudyScreen(store: store),
      ),
      _HubItem(
        keyName: 'recipe',
        title: '菜谱收藏',
        icon: Icons.restaurant_outlined,
        tint: Theme.of(context).colorScheme.tertiaryContainer,
        count: '${store.recipes.length} 道',
        screen: RecipeScreen(store: store),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('记事本')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return InkWell(
            key: ValueKey('hub-${item.keyName}'),
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => item.screen),
            ),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: item.tint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.count,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HubItem {
  const _HubItem({
    required this.keyName,
    required this.title,
    required this.icon,
    required this.tint,
    required this.count,
    required this.screen,
  });

  final String keyName;
  final String title;
  final IconData icon;
  final Color tint;
  final String count;
  final Widget screen;
}

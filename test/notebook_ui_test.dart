// 记事本 UI 测试：Hub 渲染与导航、六子功能增删改流程（内存替身）
import 'package:daily_planner/models/notebook_ledger.dart';
import 'package:daily_planner/models/notebook_reading.dart';
import 'package:daily_planner/models/notebook_recipe.dart';
import 'package:daily_planner/models/notebook_shopping.dart';
import 'package:daily_planner/modules/notebook/notebook_tab.dart';
import 'package:daily_planner/modules/notebook/screens/ledger_screen.dart';
import 'package:daily_planner/modules/notebook/screens/reading_screen.dart';
import 'package:daily_planner/modules/notebook/screens/recipe_screen.dart';
import 'package:daily_planner/modules/notebook/screens/shopping_screen.dart';
import 'package:daily_planner/modules/notebook/screens/study_screen.dart';
import 'package:daily_planner/modules/notebook/screens/trip_screen.dart';
import 'package:daily_planner/modules/notebook/widgets/notebook_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notebook_store.dart';

void main() {
  late FakeNotebookStore store;

  setUp(() {
    store = FakeNotebookStore();
  });

  Future<void> pump(WidgetTester tester, Widget widget) async {
    // 放大视口：避免 2 列网格/长表单在默认 800×600 下懒加载截断
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pump();
  }

  testWidgets('Hub 渲染六卡与条目数，点击进入购物页', (tester) async {
    await store.addLedger(
      NotebookLedger(
        id: 'l1',
        title: '工资',
        kind: 'income',
        amount: 1,
        category: '',
        date: '',
        note: '',
      ),
    );
    await pump(tester, NotebookTab(store: store));
    for (final title in ['购物清单', '收支账本', '读书清单', '旅游行程', '学习记录', '菜谱收藏']) {
      expect(find.text(title), findsWidgets);
    }
    expect(find.text('1 笔'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hub-shopping')));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingScreen), findsOneWidget);
  });

  testWidgets('购物：新建购物车与添加购物项', (tester) async {
    await pump(tester, ShoppingScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '超市');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.shoppingCarts.single.name, '超市');

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '牛奶');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.shopping.single.item, '牛奶');
  });

  testWidgets('收支：新增一笔并更新汇总', (tester) async {
    await pump(tester, LedgerScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '工资');
    await tester.enterText(find.byType(TextField).at(1), '12000');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.ledger.single.title, '工资');
    expect(find.text('结余 ¥12000'), findsOneWidget);
  });

  testWidgets('读书：新增书目', (tester) async {
    await pump(tester, ReadingScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '三体');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.reading.single.title, '三体');
  });

  testWidgets('旅游：新建行程（含一天一打卡点）', (tester) async {
    await pump(tester, TripScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '杭州三日');
    await tester.tap(find.text('加一天'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ).first,
      '2026-08-10',
    );
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ).first,
      '西湖',
    );
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.trips.single.title, '杭州三日');
    expect(store.trips.first.days.single.checkpoints.single.name, '西湖');
  });

  testWidgets('学习：新增课程并追加记录', (tester) async {
    await pump(tester, StudyScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Flutter');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flutter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '状态管理');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    expect(store.courses.first.records.single.title, '状态管理');
  });

  testWidgets('菜谱：收藏并保存配料', (tester) async {
    await pump(tester, RecipeScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '红烧肉');
    await tester.enterText(find.byType(TextField).at(2), '五花肉');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.recipes.single.ingredients, ['五花肉']);
  });

  testWidgets('收支报表入口打开并渲染', (tester) async {
    await store.addLedger(
      NotebookLedger(
        id: 'l1',
        title: '工资',
        kind: 'income',
        amount: 12000,
        category: '',
        date: '2026-08-01',
        note: '',
      ),
    );
    await pump(tester, LedgerScreen(store: store));
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();
    expect(find.byType(ReportScreen), findsOneWidget);
    expect(find.text('收支报表'), findsWidgets);
  });

  testWidgets('购物报表入口打开并渲染', (tester) async {
    await store.addShopping(
      NotebookShopping(
        id: 'i1',
        item: '牛奶',
        price: 9.5,
        category: '',
        note: '',
        cartId: '',
        date: '2026-08-01',
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    await pump(tester, ShoppingScreen(store: store));
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();
    expect(find.byType(ReportScreen), findsOneWidget);
  });
}

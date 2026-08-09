// 记事本 UI 测试：Hub 渲染与导航、六子功能抽屉增删改流程（内存替身）
import 'package:daily_planner/models/notebook_ledger.dart';
import 'package:daily_planner/models/notebook_shopping.dart';
import 'package:daily_planner/modules/notebook/notebook_tab.dart';
import 'package:daily_planner/modules/notebook/screens/ledger_screen.dart';
import 'package:daily_planner/modules/notebook/screens/reading_screen.dart';
import 'package:daily_planner/modules/notebook/screens/recipe_screen.dart';
import 'package:daily_planner/modules/notebook/screens/shopping_cart_detail_screen.dart';
import 'package:daily_planner/modules/notebook/screens/shopping_screen.dart';
import 'package:daily_planner/modules/notebook/screens/shopping_trend_screen.dart';
import 'package:daily_planner/modules/notebook/screens/study_screen.dart';
import 'package:daily_planner/modules/notebook/screens/trip_screen.dart';
import 'package:daily_planner/modules/notebook/widgets/notebook_report.dart';
import 'package:daily_planner/modules/notebook/widgets/notebook_shared.dart';
import 'package:daily_planner/modules/notebook/widgets/shopping_item_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

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

  /// 在原生日期选择器中点确认（initialDate 即目标日期时直接确认）。
  Future<void> confirmDatePicker(WidgetTester tester) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextButton),
          )
          .last,
    );
    await tester.pumpAndSettle();
  }

  /// 在原生日期选择器中点击指定日期格子后确认。
  Future<void> pickDayInDialog(WidgetTester tester, String label) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text(label),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await confirmDatePicker(tester);
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

  testWidgets('窄屏下 Hub 卡片不溢出（无 RenderFlex overflow）', (tester) async {
    // 320px 级窄屏：此前 childAspectRatio 定高导致卡片内容溢出，
    // 调试模式会在卡片下方渲染红色英文 overflow 提示
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: NotebookTab(store: store)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // 六张卡片全部可见
    for (final title in ['购物清单', '收支账本', '读书清单', '旅游行程', '学习记录', '菜谱收藏']) {
      expect(find.text(title), findsWidgets);
    }
  });

  testWidgets('购物车列表：单行记录、新建抽屉默认日期标题、点行进子页', (tester) async {
    await store.addCart(NotebookShoppingCart(
      id: 'c1', name: '周末生鲜大采购', note: null, createdAt: DateTime(2026, 8, 5, 10),
    ));
    await store.addShopping(NotebookShopping(
      id: 'i1', item: '牛奶', price: 9.5, category: '生鲜食品',
      note: '', cartId: 'c1', date: '2026-08-05', createdAt: DateTime(2026, 8, 5, 10),
    ));
    await pump(tester, ShoppingScreen(store: store));
    // 车行单行元信息：实付 ¥9.50 · 1 项
    expect(find.text('周末生鲜大采购'), findsOneWidget);
    expect(find.textContaining('¥9.50'), findsOneWidget);
    // 新建购物车抽屉：标题默认今天 yyyy年MM月dd日
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(
      find.text(
        '${now.year}年${now.month.toString().padLeft(2, '0')}月'
        '${now.day.toString().padLeft(2, '0')}日',
      ),
      findsWidgets,
    );
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    // 点车行进子页
    await tester.tap(find.text('周末生鲜大采购'));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingCartDetailScreen), findsOneWidget);
    expect(find.text('牛奶'), findsOneWidget);
  });

  testWidgets('购物车抽屉：编辑标题保存、删除购物车回收未分组', (tester) async {
    await store.addCart(NotebookShoppingCart(
      id: 'c1', name: '旧标题', note: null, createdAt: DateTime(2026, 8, 5, 10),
    ));
    await store.addShopping(NotebookShopping(
      id: 'i1', item: '苹果', price: 5, category: '生鲜食品',
      note: '', cartId: 'c1', date: '', createdAt: DateTime(2026, 8, 5, 10),
    ));
    await pump(tester, ShoppingScreen(store: store));
    // 进入子页 → 编辑抽屉
    await tester.tap(find.text('旧标题'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新标题');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.shoppingCarts.single.name, '新标题');
    // 再次编辑 → 删除购物车
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除购物车'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(store.shoppingCarts, isEmpty);
    expect(store.shopping.single.cartId, '');
  });

  testWidgets('收支：新增一笔并更新汇总（默认支出首项枚举）', (tester) async {
    await pump(tester, LedgerScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '晚餐');
    await tester.enterText(find.byType(TextField).at(1), '50');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final saved = store.ledger.single;
    expect(saved.title, '晚餐');
    expect(saved.kind, 'expense');
    expect(saved.category, '餐饮'); // 支出枚举默认首项
    expect(find.text('结余'), findsOneWidget);
    expect(find.text('-¥50.00'), findsOneWidget);
  });

  testWidgets('收支：金额非法拦截、切收入联动枚举重置并保存', (tester) async {
    await pump(tester, LedgerScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '工资');
    await tester.enterText(find.byType(TextField).at(1), '-5');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.ledger, isEmpty);
    expect(find.text('请输入有效金额（不小于 0）'), findsOneWidget);
    // 切到收入：消费类型联动重置为收入首项「工资」
    await tester.tap(
      find.widgetWithText(SegmentedButton<String>, '收入'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '12000');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.ledger.single.kind, 'income');
    expect(store.ledger.single.category, '工资');
  });

  testWidgets('收支报表入口打开并渲染，当前区间右箭头禁用', (tester) async {
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
    await tester.tap(find.byIcon(Icons.bar_chart_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ReportScreen), findsOneWidget);
    expect(find.text('收支报表'), findsWidgets);
    expect(find.text('本月结余'), findsOneWidget); // 结余总览卡（规格 C9）
    // 当前周期右箭头禁用，禁止进入未来区间
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull);
    // 上一区间后右箭头恢复可用
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    final next2 = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next2.onPressed, isNotNull);
  });

  testWidgets('读书：新增书目（状态徽标选择）与编辑删除', (tester) async {
    await pump(tester, ReadingScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '三体');
    await tester.tap(find.text('读完'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.reading.single.title, '三体');
    expect(store.reading.single.status, 'done');
    // 点行进编辑抽屉 → 删除
    await tester.tap(find.text('三体'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(store.reading, isEmpty);
  });

  testWidgets('旅游：新建行程 → 详情加一天一打卡点（计费类型多选）', (tester) async {
    await pump(tester, TripScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '杭州三日');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.trips.single.title, '杭州三日');
    // 点行进详情
    await tester.tap(find.text('杭州三日'));
    await tester.pumpAndSettle();
    // 加一天抽屉：仅填标签（日期可选）
    await tester.tap(find.text('加一天'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'D1');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    // 加打卡点：名称 + 计费类型多选 + 金额
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '西湖');
    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.tap(find.text('门票'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('交通'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final trip = store.trips.single;
    expect(trip.days.single.label, 'D1');
    final cp = trip.days.single.checkpoints.single;
    expect(cp.name, '西湖');
    expect(cp.billings.map((b) => b.type), containsAll(['门票', '交通']));
    expect(trip.totalCost, 45, reason: '金额只记在首个计费类型上，总额不重复累计');
  });

  testWidgets('旅游：结束日期早于开始被拦截不保存', (tester) async {
    await pump(tester, TripScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '成都五日');
    // 开始日期 = 今天（直接确认）
    await tester.tap(find.byType(DateField).at(0));
    await tester.pumpAndSettle();
    await confirmDatePicker(tester);
    // 结束日期 = 上个月 15 号（一定早于今天）
    await tester.tap(find.byType(DateField).at(1));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byIcon(Icons.chevron_left),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await pickDayInDialog(tester, '15');
    // 保存应被拦截且不落库
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.trips, isEmpty);
    expect(find.text('结束日期不得早于开始日期'), findsOneWidget);
  });

  testWidgets('学习：新增课程并追加记录（抽屉）', (tester) async {
    await pump(tester, StudyScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Flutter');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.courses.single.title, 'Flutter');
    // 点行进课程详情 → 添加记录抽屉
    await tester.tap(find.text('Flutter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '状态管理');
    await tester.enterText(find.byType(TextField).at(1), 'Provider 原理');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final record = store.courses.first.records.single;
    expect(record.title, '状态管理');
    expect(record.content, 'Provider 原理');
  });

  testWidgets('菜谱：收藏并保存配料、难度枚举选择', (tester) async {
    await pump(tester, RecipeScreen(store: store));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '红烧肉');
    await tester.enterText(find.byType(TextField).at(2), '五花肉');
    await tester.tap(find.text('困难'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.recipes.single.ingredients, ['五花肉']);
    expect(store.recipes.single.difficulty, 'hard');
  });

  testWidgets('购物报表入口打开并渲染饼图', (tester) async {
    await store.addShopping(
      NotebookShopping(
        id: 'i1',
        item: '牛奶',
        price: 9.5,
        category: '生鲜食品',
        note: '',
        cartId: '',
        date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    await pump(tester, ShoppingScreen(store: store));
    await tester.tap(find.byIcon(Icons.insert_chart_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingTrendScreen), findsOneWidget);
    expect(find.text('生鲜食品'), findsWidgets);
  });

  testWidgets('购物项抽屉：金额/类型/日期保存、折叠展开、金额非法拦截', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showShoppingItemSheet(context, store: store, cartId: 'c1'),
              child: const Text('打开抽屉'),
            ),
          ),
        ),
      ),
    );
    // 窄视口下枚举才需要折叠（抽屉内宽度约 360px）
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    await tester.pump();
    await tester.tap(find.text('打开抽屉'));
    await tester.pumpAndSettle();
    // 枚举折叠态：展开按钮存在
    expect(find.textContaining('展开全部'), findsOneWidget);
    // 输入名称与金额
    await tester.enterText(find.byType(TextField).at(0), '三文鱼');
    await tester.enterText(find.byType(TextField).at(1), '36');
    // 展开后选择「生鲜食品」
    await tester.tap(find.textContaining('展开全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生鲜食品'));
    // 日期字段点击会弹系统选择器，跳过（DateField 已有独立测试）
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final saved = store.shopping.single;
    expect(saved.item, '三文鱼');
    expect(saved.price, 36);
    expect(saved.category, '生鲜食品');
    // 非法金额：负数拦截，不新增
    await tester.tap(find.text('打开抽屉'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '酸奶');
    await tester.enterText(find.byType(TextField).at(1), '-5');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.shopping, hasLength(1));
    expect(find.textContaining('金额'), findsWidgets); // 就近错误提示
  });
}

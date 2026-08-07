// 购物消费趋势报表测试：周期聚合、禁未来、UI 渲染
import 'package:daily_planner/models/notebook_shopping.dart';
import 'package:daily_planner/modules/notebook/screens/shopping_trend_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notebook_store.dart';

NotebookShopping _item(String id, String category, num price, String date) =>
    NotebookShopping(
      id: id,
      item: id,
      price: price,
      category: category,
      note: '',
      cartId: '',
      date: date,
      createdAt: DateTime(2026, 8, 1),
    );

void main() {
  group('buildCategorySlices - 周期聚合', () {
    test('按月：只统计锚点所在月，按分类聚合且降序', () {
      final anchor = DateTime(2026, 8, 1);
      final items = [
        _item('a', '生鲜食品', 100, '2026-08-05'),
        _item('b', '日用品', 50, '2026-08-06'),
        _item('c', '生鲜食品', 30, '2026-08-07'),
        _item('d', '生鲜食品', 999, '2026-07-31'), // 上月，排除
      ];
      final slices = buildCategorySlices(items, anchor, ShoppingPeriod.month);
      expect(slices[0].label, '生鲜食品');
      expect(slices[0].value, 130);
      expect(slices[0].percent, closeTo(130 / 180, 0.0001));
      expect(slices[1].label, '日用品');
      expect(slices[1].value, 50);
    });

    test('空 date 视为今日；空/未知分类归入「其他」', () {
      final now = DateTime.now();
      final anchor = periodStart(now, ShoppingPeriod.month);
      final items = [
        _item('a', '', 20, ''), // 今日 + 无分类
        _item('b', '不存在分类', 10, ''),
      ];
      final slices = buildCategorySlices(
          items, anchor, ShoppingPeriod.month, now: now);
      expect(slices, hasLength(1));
      expect(slices.single.label, '其他');
      expect(slices.single.value, 30);
    });

    test('周期为空返回空列表', () {
      final slices =
          buildCategorySlices([], DateTime(2026, 8, 1), ShoppingPeriod.month);
      expect(slices, isEmpty);
    });
  });

  group('周期导航与禁未来', () {
    test('isCurrentPeriod：今天/本月/今年为当前周期', () {
      final now = DateTime(2026, 8, 6, 15);
      expect(
          isCurrentPeriod(DateTime(2026, 8, 6), ShoppingPeriod.day, now: now),
          isTrue);
      expect(
          isCurrentPeriod(DateTime(2026, 8, 1), ShoppingPeriod.month,
              now: now),
          isTrue);
      expect(
          isCurrentPeriod(DateTime(2026, 1, 1), ShoppingPeriod.year, now: now),
          isTrue);
    });

    test('shiftPeriod 越过当前周期时（下个月）isCurrentPeriod 为 false → UI 禁用右箭头', () {
      final now = DateTime(2026, 8, 6);
      final next = shiftPeriod(
          periodStart(now, ShoppingPeriod.month), ShoppingPeriod.month, 1);
      expect(isCurrentPeriod(next, ShoppingPeriod.month, now: now), isFalse);
    });
  });

  testWidgets('报表 UI：图例渲染、按月切换、右箭头禁用', (tester) async {
    final store = FakeNotebookStore();
    await store.addShopping(_item('a', '生鲜食品', 100, '2026-08-05'));
    await store.addShopping(_item('b', '日用品', 50, '2026-08-06'));
    await tester.pumpWidget(
        MaterialApp(home: ShoppingTrendScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('生鲜食品'), findsWidgets);
    expect(find.text('¥100.00'), findsWidgets);
    // 右箭头禁用（当前月）
    final nextBtn = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
    );
    expect(nextBtn.onPressed, isNull);
    // 切到按天，字段标签变化
    await tester.tap(find.text('按天'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(find.text('${now.year}年${now.month}月${now.day}日'), findsOneWidget);
  });
}

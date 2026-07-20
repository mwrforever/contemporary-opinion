import 'package:daily_planner/modules/tasks/task_list.dart';
import 'package:daily_planner/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// FilterTabBar 组件测试（T01）。
///
/// 覆盖：默认选中（TabController 初始索引）、四 Tab 文案与计数、
/// 切换时触发 onChanged 回调。
void main() {
  group('FilterTabBar - 默认选中 / 文案计数 / 切换回调', () {
    testWidgets('默认选中全部(all)，显示三 Tab 文案与计数', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: FilterTabBar(
            filter: TaskFilter.all,
            onChanged: (_) {},
            total: 5,
            active: 2,
            conflict: 3,
            overdue: 1,
          ),
        ),
      ));

      // 默认选中全部：TabController 初始索引为 all 的索引 0
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.controller!.index, 0);

      // 三 Tab 与计数
      final texts = tester
          .widgetList<Tab>(find.byType(Tab))
          .map((t) => t.text ?? '')
          .toList();
      expect(texts, hasLength(4));
      expect(texts[0], contains('全部'));
      expect(texts[0], contains('5'));
      expect(texts[1], contains('待办'));
      expect(texts[1], contains('2'));
      expect(texts[2], contains('逾期'));
      expect(texts[2], contains('1'));
      expect(texts[3], contains('冲突'));
      expect(texts[3], contains('3'));
    });

    testWidgets('切换 Tab 触发 onChanged 回调（逾期 / 冲突）', (tester) async {
      TaskFilter? changed;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: FilterTabBar(
            filter: TaskFilter.all,
            onChanged: (f) => changed = f,
            total: 5,
            active: 2,
            conflict: 3,
            overdue: 1,
          ),
        ),
      ));

      await tester.tap(find.byType(Tab).at(1)); // 待办
      await tester.pumpAndSettle();
      expect(changed, TaskFilter.active);

      await tester.tap(find.byType(Tab).at(2)); // 逾期
      await tester.pumpAndSettle();
      expect(changed, TaskFilter.overdue);

      await tester.tap(find.byType(Tab).at(3)); // 冲突
      await tester.pumpAndSettle();
      expect(changed, TaskFilter.conflict);
    });

    testWidgets('初始选中冲突时，控制器默认索引为 2', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: FilterTabBar(
            filter: TaskFilter.conflict,
            onChanged: (_) {},
            total: 1,
            active: 0,
            conflict: 1,
            overdue: 1,
          ),
        ),
      ));
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.controller!.index, 3);
    });
  });
}

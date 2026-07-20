import 'package:daily_planner/modules/notebook/widgets/notebook_hub_card.dart';
import 'package:daily_planner/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// NotebookHubCard 组件测试（T03）。
///
/// 覆盖：渲染标题与计数、去加号（无新增图标）、点击触发导航回调。
void main() {
  group('NotebookHubCard - 渲染 / 无加号 / 点击导航', () {
    testWidgets('渲染标题与计数，且不含加号图标', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 240,
            child: NotebookHubCard(
              icon: Icons.luggage_rounded,
              title: '旅游行程',
              count: 3,
              onTap: () {},
            ),
          ),
        ),
      ));

      expect(find.text('旅游行程'), findsOneWidget);
      expect(find.text('3 条'), findsOneWidget);
      // 决策 B：去加号，不应出现新增/加号图标
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('点击触发 onTap 导航回调', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 240,
            child: NotebookHubCard(
              icon: Icons.luggage_rounded,
              title: '旅游行程',
              count: 3,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ));

      // 图标位于 InkWell 内，点击即触发导航回调
      await tester.tap(find.byIcon(Icons.luggage_rounded));
      expect(tapped, isTrue);
    });
  });

  group('NotebookHubCard - 居中对齐（T7 增量）', () {
    testWidgets('图标/标题/计数整体居中 (CrossAxisAlignment.center)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 240,
            child: NotebookHubCard(
              icon: Icons.luggage_rounded,
              title: '旅游行程',
              count: 3,
              onTap: () {},
            ),
          ),
        ),
      ));

      final column = tester.widget<Column>(
        find.descendant(
          of: find.byType(NotebookHubCard),
          matching: find.byType(Column),
        ),
      );
      expect(column.crossAxisAlignment, CrossAxisAlignment.center,
          reason: 'T7 决策：hub 卡内容整体居中');
    });
  });
}

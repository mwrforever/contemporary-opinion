import 'package:daily_planner/modules/notebook/widgets/notebook_shared.dart';
import 'package:daily_planner/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// DateField 组件测试（T05）。
///
/// 覆盖：显示初始 value、空值时显示 yyyy-MM-dd 占位提示、
/// 选中日期后回填 yyyy-MM-dd 格式（通过原生 DatePicker）。
void main() {
  group('DateField - yyyy-MM-dd 回填 / 默认清空', () {
    testWidgets('显示初始 value', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DateField(
            label: '开始',
            value: '2026-07-20',
            onChanged: (_) {},
          ),
        ),
      ));
      expect(find.text('2026-07-20'), findsOneWidget);
    });

    testWidgets('空 value 显示 yyyy-MM-dd 占位提示', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DateField(
            label: '开始',
            value: '',
            onChanged: (_) {},
          ),
        ),
      ));
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.decoration?.hintText, 'yyyy-MM-dd');
    });

    testWidgets('选中日期后回填 yyyy-MM-dd 格式', (tester) async {
      String? changed;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DateField(
            label: '开始',
            value: '2026-07-15', // 作为 DatePicker 的 initialDate
            onChanged: (v) => changed = v,
          ),
        ),
      ));

      // 点击唤起原生日期选择器
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // 直接确认（initialDate 已为 2026-07-15，无需改选）——取对话框内最后一个
      // TextButton 作为确认按钮（locale 无关）。
      await tester.tap(
        find
            .descendant(
              of: find.byType(DatePickerDialog),
              matching: find.byType(TextButton),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(changed, isNotNull);
      expect(changed, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(changed, '2026-07-15');
    });
  });
}

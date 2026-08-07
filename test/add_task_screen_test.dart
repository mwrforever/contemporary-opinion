// 新建任务页测试：必填校验、过去时间拦截、保存进 Store、倒计时录入
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/modules/tasks/add_task_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late FakeTaskStore store;

  setUp(() {
    store = FakeTaskStore();
  });

  Future<void> pumpScreen(WidgetTester tester, {Task? editTask}) async {
    // 放大视口，使长表单所有字段与保存按钮一次性构建，避免懒加载滚动
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AddTaskScreen(
          store: store,
          reminder: buildFakeReminder(),
          editTask: editTask,
        ),
      ),
    );
  }

  testWidgets('标题必填校验', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pump();
    expect(find.text('请输入标题'), findsOneWidget);
  });

  testWidgets('编辑已过去时间的任务被拦截', (tester) async {
    final past = Task(
      id: 'past',
      title: '过期任务',
      scheduledTime: DateTime(2020, 1, 1, 8),
      createdAt: DateTime(2020, 1, 1),
      notificationId: 1,
    );
    await pumpScreen(tester, editTask: past);
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pump();
    expect(find.text('开始时间不能早于现在'), findsOneWidget);
  });

  testWidgets('保存新任务进入 Store', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextFormField).first, '开会');
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pumpAndSettle();
    expect(store.all.single.title, '开会');
  });

  testWidgets('倒计时模式保存分钟数', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('倒计时'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '开会');
    await tester.enterText(find.byType(TextFormField).at(1), '15');
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pumpAndSettle();
    final saved = store.all.single;
    expect(saved.countdownMinutes, 15);
    expect(saved.scheduledTime!.isAfter(DateTime.now()), isTrue);
  });
}

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

  testWidgets('标题输入框关闭 autocorrect 且保留联想（荣耀机型软键盘修复）', (tester) async {
    await pumpScreen(tester);
    final title = tester.widget<TextField>(find.byType(TextField).first);
    expect(title.autocorrect, isFalse);
    expect(title.enableSuggestions, isTrue);
  });

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

  testWidgets('毫秒级过期拦截：同一分钟内已过时刻也不允许保存', (tester) async {
    // 任务时刻 = 30 秒前（与 now 同分钟），毫秒级判定为已过期
    final past = Task(
      id: 'same-min',
      title: '刚过期',
      scheduledTime: DateTime.now().subtract(const Duration(seconds: 30)),
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      notificationId: 1,
    );
    await pumpScreen(tester, editTask: past);
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pump();
    expect(find.text('开始时间不能早于现在'), findsOneWidget);
  });

  testWidgets('资源冲突：允许保存但弹警告，且任务标记冲突不执行', (tester) async {
    store.seed(Task(
      id: 'conflict-src',
      title: '占用会议室',
      scheduledTime: DateTime.now().add(const Duration(minutes: 1)),
      durationMinutes: 60,
      resource: '会议室A',
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    ));
    // 与生产一致：新增页 push 在列表页之上，保存后 SnackBar 由列表页 Scaffold 承接
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => AddTaskScreen(
                      store: store,
                      reminder: buildFakeReminder(),
                    ),
                  ),
                ),
                child: const Text('打开新增'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开新增'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '开会');
    await tester.enterText(find.byType(TextFormField).at(1), '会议室A');
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pumpAndSettle();
    final saved = store.all.firstWhere((t) => t.title == '开会');
    expect(saved.hasPendingConflict, isTrue);
    expect(saved.effective, isFalse);
    // 已返回列表页，冲突警告 SnackBar 展示
    expect(find.textContaining('资源冲突'), findsOneWidget);
  });

  testWidgets('保存新任务进入 Store', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextFormField).first, '开会');
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pumpAndSettle();
    expect(store.all.single.title, '开会');
  });

  testWidgets('新建任务资源占用时长默认 1 分钟', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextFormField).first, '会议室预约');
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pumpAndSettle();
    expect(store.all.single.durationMinutes, 1);
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

  testWidgets('倒计时重复次数 5 保存为 DELAYED 间隔任务', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('倒计时'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '喝水');
    await tester.enterText(find.byType(TextFormField).at(1), '30');
    await tester.enterText(find.byType(TextFormField).at(2), '5');
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pumpAndSettle();
    final saved = store.all.single;
    expect(saved.triggerType, TriggerType.delayed);
    expect(saved.intervalSeconds, 1800);
    expect(saved.maxRepeats, 5);
    expect(saved.repeat, RepeatType.none);
  });

  testWidgets('倒计时重复次数 -1 保存为一直重复的 DELAYED 任务', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('倒计时'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '喝水');
    await tester.enterText(find.byType(TextFormField).at(1), '10');
    await tester.enterText(find.byType(TextFormField).at(2), '-1');
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pumpAndSettle();
    final saved = store.all.single;
    expect(saved.triggerType, TriggerType.delayed);
    expect(saved.maxRepeats, -1);
    expect(saved.repeatsForever, isTrue);
  });

  testWidgets('倒计时默认重复次数 1 保存为一次性任务', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('倒计时'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '吃药');
    await tester.enterText(find.byType(TextFormField).at(1), '10');
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pumpAndSettle();
    final saved = store.all.single;
    expect(saved.triggerType, TriggerType.once);
    expect(saved.intervalSeconds, isNull);
    expect(saved.maxRepeats, isNull);
  });

  testWidgets('编辑倒计时任务可回写间隔与重复次数', (tester) async {
    final delayed = Task(
      id: 'delay',
      title: '喝水',
      scheduledTime: DateTime.now().add(const Duration(minutes: 30)),
      countdownMinutes: 30,
      triggerType: TriggerType.delayed,
      intervalSeconds: 1800,
      maxRepeats: 3,
      repeatCount: 0,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    );
    store.seed(delayed);
    await pumpScreen(tester, editTask: delayed);
    // 编辑模式还原为倒计时 + 间隔/次数字段
    await tester.enterText(find.byType(TextFormField).at(1), '15');
    await tester.enterText(find.byType(TextFormField).at(2), '8');
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pumpAndSettle();
    final saved = store.getById('delay')!;
    expect(saved.triggerType, TriggerType.delayed);
    expect(saved.intervalSeconds, 900);
    expect(saved.maxRepeats, 8);
  });

  testWidgets('编辑倒计时任务把重复次数改为 1 后退化为一次性', (tester) async {
    final delayed = Task(
      id: 'delay-off',
      title: '喝水',
      scheduledTime: DateTime.now().add(const Duration(minutes: 30)),
      countdownMinutes: 30,
      triggerType: TriggerType.delayed,
      intervalSeconds: 1800,
      maxRepeats: 3,
      repeatCount: 0,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    );
    store.seed(delayed);
    await pumpScreen(tester, editTask: delayed);
    await tester.enterText(find.byType(TextFormField).at(2), '1');
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pumpAndSettle();
    final saved = store.getById('delay-off')!;
    expect(saved.triggerType, TriggerType.once);
    expect(saved.intervalSeconds, isNull);
    expect(saved.maxRepeats, isNull);
  });
}

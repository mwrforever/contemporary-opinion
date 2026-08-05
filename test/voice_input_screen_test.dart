// 语音规划页测试：离线文本/NLP、云端录音流程、四态预览、确认添加计数
import 'dart:async';

import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/modules/tasks/voice_input_screen.dart';
import 'package:daily_planner/services/aliyun_asr_service.dart';
import 'package:daily_planner/services/aliyun_schedule_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// 假 ASR：立即回传固定文本
class FakeAsr extends AliyunAsrService {
  FakeAsr(this.transcript) : super(apiKey: '');

  final String transcript;
  final Completer<void> _done = Completer<void>();
  int stopCalls = 0;

  @override
  Future<String> transcribe({
    required void Function(String) onPartial,
  }) async {
    onPartial(transcript);
    // 模拟真实录音：等待用户点击停止后才返回
    await _done.future;
    return transcript;
  }

  @override
  void stop() {
    stopCalls++;
    if (!_done.isCompleted) _done.complete();
  }
}

/// 假排期：返回固定候选
class FakeSchedule extends AliyunScheduleService {
  FakeSchedule(this.result) : super(apiKey: '');

  final List<ScheduledTask> result;

  @override
  Future<List<ScheduledTask>> schedule(
    String transcript, {
    List<Task> existing = const [],
    DateTime? now,
  }) async {
    return result;
  }
}

void main() {
  late FakeTaskStore store;

  setUp(() {
    store = FakeTaskStore();
  });

  DateTime future({int days = 1, int hour = 10}) {
    final base = DateTime.now().add(Duration(days: days));
    return DateTime(base.year, base.month, base.day, hour);
  }

  /// 返回语音页路由 Future；确认添加后由调用方 await 取结果
  Future<Future<VoicePlanResult?>> pumpVoice(
    WidgetTester tester, {
    AliyunAsrService? asr,
    AliyunScheduleService? schedule,
    bool? cloudEnabled,
  }) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navKey, home: const Scaffold()),
    );
    final routeFuture = navKey.currentState!.push<VoicePlanResult>(
      MaterialPageRoute(
        builder: (_) => VoiceInputScreen(
          store: store,
          reminder: buildFakeReminder(),
          asr: asr,
          schedule: schedule,
          cloudEnabled: cloudEnabled,
          requestMicPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return routeFuture;
  }

  testWidgets('离线文本模式：无录音按钮，NLP 解析后进入预览', (tester) async {
    await pumpVoice(tester, cloudEnabled: false);
    expect(find.byIcon(Icons.mic), findsNothing);
    await tester.enterText(
      find.byType(TextField),
      '明天上午10点开会',
    );
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(find.text('开会'), findsOneWidget);
  });

  testWidgets('云端录音流程：录音→停止→转写→解析→预览', (tester) async {
    final asr = FakeAsr('吃药提醒');
    final schedule = FakeSchedule([
      ScheduledTask(title: '吃药', scheduledTime: future()),
    ]);
    await pumpVoice(tester, asr: asr, schedule: schedule, cloudEnabled: true);
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    expect(find.text('识别中…（点击下方停止）'), findsOneWidget);
    await tester.tap(find.text('停止'));
    await tester.pumpAndSettle();
    expect(asr.stopCalls, 1);
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(find.text('吃药'), findsOneWidget);
  });

  testWidgets('四态：资源冲突卡可确认覆盖', (tester) async {
    store.seed(Task(
      id: 'base',
      title: '产品周会',
      scheduledTime: future(hour: 10),
      resource: '会议室A',
      durationMinutes: 60,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    ));
    final schedule = FakeSchedule([
      ScheduledTask(
        title: '面试评审',
        scheduledTime: future(hour: 10, days: 1).add(const Duration(minutes: 30)),
        resource: '会议室A',
        durationMinutes: 60,
      ),
    ]);
    await pumpVoice(tester, schedule: schedule, cloudEnabled: false);
    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(find.text('冲突待处理'), findsOneWidget);
    await tester.tap(find.text('确认覆盖'));
    await tester.pumpAndSettle();
    expect(find.text('冲突待处理'), findsNothing);
  });

  testWidgets('四态：时间待定卡提供设时间', (tester) async {
    final schedule = FakeSchedule([
      const ScheduledTask(title: '取快递'),
    ]);
    await pumpVoice(tester, schedule: schedule, cloudEnabled: false);
    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(find.text('时间待定'), findsOneWidget);
    expect(find.text('设时间'), findsOneWidget);
  });

  testWidgets('四态：已过去任务默认跳过不计数', (tester) async {
    final schedule = FakeSchedule([
      ScheduledTask(
        title: '昨天的事',
        scheduledTime: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);
    await pumpVoice(tester, schedule: schedule, cloudEnabled: false);
    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(find.text('已过去'), findsOneWidget);
    expect(find.text('将添加 0 条 · 跳过 1 条'), findsOneWidget);
  });

  testWidgets('确认添加：计数正确且冲突项不生效', (tester) async {
    store.seed(Task(
      id: 'base',
      title: '产品周会',
      scheduledTime: future(hour: 10),
      resource: '会议室A',
      durationMinutes: 60,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    ));
    final schedule = FakeSchedule([
      ScheduledTask(title: '普通任务', scheduledTime: future(hour: 15)),
      ScheduledTask(
        title: '冲突任务',
        scheduledTime: future(hour: 10, days: 1).add(const Duration(minutes: 30)),
        resource: '会议室A',
        durationMinutes: 60,
      ),
      ScheduledTask(
        title: '昨天的事',
        scheduledTime: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);
    final routeFuture = await pumpVoice(
      tester,
      schedule: schedule,
      cloudEnabled: false,
    );
    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(find.text('将添加 2 条 · 跳过 1 条'), findsOneWidget);
    await tester.tap(find.text('确认添加'));
    await tester.pumpAndSettle();
    final result = await routeFuture;
    expect(result, isNotNull);
    expect(result!.added, 2);
    expect(result.conflict, 1);
    expect(result.skipped, 1);
    final titles = store.all.map((t) => t.title).toSet();
    expect(titles, containsAll(['产品周会', '普通任务', '冲突任务']));
    expect(titles, isNot(contains('昨天的事')));
    expect(store.all.firstWhere((t) => t.title == '冲突任务').effective, isFalse);
  });
}

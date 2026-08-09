// Task 模型 toMap/fromMap 单元测试：全字段 round-trip 与默认值
import 'package:daily_planner/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap 全字段 round-trip', () {
    final original = Task(
      id: 't-roundtrip',
      title: '全字段任务',
      scheduledTime: DateTime(2026, 8, 5, 14, 0),
      countdownMinutes: 30,
      countdownSeconds: 12,
      repeat: RepeatType.custom,
      customWeekdays: const [1, 3, 5],
      status: TaskStatus.done,
      source: TaskSource.voice,
      completedAt: DateTime(2026, 8, 5, 14, 5),
      createdAt: DateTime(2026, 8, 5, 8, 0),
      notificationId: 42,
      resource: '会议室A',
      conflictState: ConflictState.confirmedOverride,
      effective: true,
      durationMinutes: 90,
      ringSeconds: 30,
      note: '语音备注',
      triggerType: TriggerType.recurring,
      freqType: FreqType.week,
      freqInterval: 2,
      endAt: DateTime(2026, 12, 31),
      intervalSeconds: 1800,
      maxRepeats: 5,
      repeatCount: 2,
      nextFireTime: DateTime(2026, 8, 6, 14, 30),
      prevFireTime: DateTime(2026, 8, 6, 14, 0),
    );

    final restored = Task.fromMap(original.toMap(userId: 1));
    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.scheduledTime, original.scheduledTime);
    expect(restored.countdownMinutes, original.countdownMinutes);
    expect(restored.countdownSeconds, original.countdownSeconds);
    expect(restored.repeat, RepeatType.custom);
    expect(restored.customWeekdays, [1, 3, 5]);
    expect(restored.status, TaskStatus.done);
    expect(restored.source, TaskSource.voice);
    expect(restored.completedAt, original.completedAt);
    expect(restored.createdAt, original.createdAt);
    expect(restored.notificationId, 42);
    expect(restored.resource, '会议室A');
    expect(restored.conflictState, ConflictState.confirmedOverride);
    expect(restored.effective, isTrue);
    expect(restored.durationMinutes, 90);
    expect(restored.ringSeconds, 30);
    expect(restored.note, '语音备注');
    expect(restored.triggerType, TriggerType.recurring);
    expect(restored.freqType, FreqType.week);
    expect(restored.freqInterval, 2);
    expect(restored.endAt, DateTime(2026, 12, 31));
    expect(restored.intervalSeconds, 1800);
    expect(restored.maxRepeats, 5);
    expect(restored.repeatCount, 2);
    expect(restored.nextFireTime, DateTime(2026, 8, 6, 14, 30));
    expect(restored.prevFireTime, DateTime(2026, 8, 6, 14, 0));
  });

  test('toMap 携带 user_id 且 effective 转 0/1、weekdays 为 JSON 数组', () {
    final task = Task(
      id: 't-map',
      title: '映射检查',
      repeat: RepeatType.weekdays,
      customWeekdays: const [1, 2, 3, 4, 5],
      conflictState: ConflictState.pendingConflict,
      effective: false,
      createdAt: DateTime(2026, 8, 5),
      notificationId: 1,
    );
    final map = task.toMap(userId: 7);
    expect(map['user_id'], 7);
    expect(map['effective'], 0);
    expect(map['custom_weekdays'], '[1,2,3,4,5]');
    expect(map['repeat'], 'weekdays');
    expect(map['conflict_state'], 'pendingConflict');
  });

  test('fromMap 对缺失/非法枚举回退默认值', () {
    final task = Task.fromMap({
      'id': 't-fallback',
      'title': '容错',
      'created_at': '2026-08-05T00:00:00.000',
    });
    expect(task.repeat, RepeatType.none);
    expect(task.status, TaskStatus.pending);
    expect(task.source, TaskSource.manual);
    expect(task.conflictState, ConflictState.none);
    expect(task.effective, isTrue);
    expect(task.durationMinutes, 0);
    expect(task.customWeekdays, isEmpty);
    expect(task.triggerType, TriggerType.once);
    expect(task.freqType, isNull);
    expect(task.freqInterval, 1);
    expect(task.repeatCount, 0);
  });

  test('fromMap 兼容旧数据：missed 归 pending、重复任务推导 recurring', () {
    final task = Task.fromMap({
      'id': 't-old',
      'title': '旧数据',
      'created_at': '2026-08-05T00:00:00.000',
      'status': 'missed',
      'repeat': 'daily',
    });
    expect(task.status, TaskStatus.pending);
    expect(task.triggerType, TriggerType.recurring);
    expect(task.freqType, FreqType.day);
  });

  test('倒计时重复：nextFireFor 按间隔与次数推进，达到上限后死亡', () {
    final task = Task(
      id: 't-delay',
      title: '喝水',
      scheduledTime: DateTime(2026, 8, 5, 8, 0),
      triggerType: TriggerType.delayed,
      intervalSeconds: 1800,
      maxRepeats: 3,
      repeatCount: 1,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    );
    final now = DateTime(2026, 8, 5, 8, 10);
    expect(task.nextFireFor(now), DateTime(2026, 8, 5, 8, 30));
    // 未达到上限：仍非死任务
    expect(task.isDeadDoneAt(now), isFalse);
    // 达到上限后：死亡
    final exhausted = Task(
      id: 't-delay-done',
      title: '喝水',
      scheduledTime: DateTime(2026, 8, 5, 8, 0),
      triggerType: TriggerType.delayed,
      intervalSeconds: 1800,
      maxRepeats: 3,
      repeatCount: 3,
      status: TaskStatus.done,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    );
    expect(exhausted.nextFireFor(now), isNull);
    expect(exhausted.isDeadDoneAt(now), isTrue);
  });

  test('倒计时重复：maxRepeats=-1 一直重复，永不死亡', () {
    final forever = Task(
      id: 't-forever',
      title: '无限喝水',
      scheduledTime: DateTime(2026, 8, 5, 8, 0),
      triggerType: TriggerType.delayed,
      intervalSeconds: 1800,
      maxRepeats: -1,
      repeatCount: 3,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    );
    expect(forever.repeatsForever, isTrue);
    // 次数持续增长仍有下一次触发，不因次数大而终止
    final now = DateTime(2026, 8, 5, 8, 10);
    expect(forever.nextFireFor(now), DateTime(2026, 8, 5, 9, 30));
    // 一直重复的任务即使已完成也仍有未来实例（不应落入「死任务」口径）
    final doneForever = Task(
      id: 't-forever-done',
      title: '无限喝水',
      scheduledTime: DateTime(2026, 8, 5, 8, 0),
      triggerType: TriggerType.delayed,
      intervalSeconds: 1800,
      maxRepeats: -1,
      repeatCount: 1,
      status: TaskStatus.done,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    );
    expect(doneForever.isDeadDoneAt(now), isFalse);
  });
}

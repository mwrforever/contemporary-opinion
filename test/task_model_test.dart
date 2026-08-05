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
  });
}

import 'dart:io';

import 'package:hive/hive.dart';
import 'package:daily_planner/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 模型单元测试。
///
/// 覆盖：构造默认值、isRepeating / isDone getter、枚举完整性，
/// 以及手写 Hive 适配器（TaskAdapter）的写入-读出 round-trip。
void main() {
  group('Task - 构造与字段', () {
    test('构造默认值正确', () {
      final created = DateTime(2026, 7, 14, 8, 0);
      final task = Task(
        id: 't1',
        title: '测试任务',
        createdAt: created,
        notificationId: 1,
      );
      expect(task.id, 't1');
      expect(task.title, '测试任务');
      expect(task.scheduledTime, isNull);
      expect(task.countdownMinutes, isNull);
      expect(task.repeat, RepeatType.none);
      expect(task.customWeekdays, isEmpty);
      expect(task.status, TaskStatus.pending);
      expect(task.source, TaskSource.manual);
      expect(task.completedAt, isNull);
      expect(task.createdAt, created);
      expect(task.notificationId, 1);
    });

    test('可显式设置全部字段', () {
      final task = Task(
        id: 't2',
        title: '吃药',
        scheduledTime: DateTime(2026, 7, 14, 21, 0),
        countdownMinutes: 30,
        repeat: RepeatType.custom,
        customWeekdays: const [1, 3, 5],
        status: TaskStatus.done,
        source: TaskSource.voice,
        completedAt: DateTime(2026, 7, 14, 21, 5),
        createdAt: DateTime(2026, 7, 14, 20, 0),
        notificationId: 7,
      );
      expect(task.scheduledTime, DateTime(2026, 7, 14, 21, 0));
      expect(task.countdownMinutes, 30);
      expect(task.repeat, RepeatType.custom);
      expect(task.customWeekdays, const [1, 3, 5]);
      expect(task.status, TaskStatus.done);
      expect(task.source, TaskSource.voice);
      expect(task.completedAt, DateTime(2026, 7, 14, 21, 5));
      expect(task.notificationId, 7);
    });
  });

  group('Task - getter', () {
    test('isRepeating 对各重复类型正确', () {
      Task make(RepeatType r, [List<int> wd = const []]) => Task(
            id: 'x',
            title: 't',
            repeat: r,
            customWeekdays: wd,
            createdAt: DateTime(2026, 7, 14),
            notificationId: 1,
          );
      expect(make(RepeatType.none).isRepeating, isFalse,
          reason: 'none 不应视为重复');
      expect(make(RepeatType.daily).isRepeating, isTrue);
      expect(make(RepeatType.weekly).isRepeating, isTrue);
      expect(make(RepeatType.weekdays).isRepeating, isTrue);
      expect(make(RepeatType.custom, [1, 3, 5]).isRepeating, isTrue);
    });

    test('isDone 仅对 done 状态为真', () {
      final pending = Task(
          id: 'p',
          title: 't',
          status: TaskStatus.pending,
          createdAt: DateTime.now(),
          notificationId: 1);
      final done = Task(
          id: 'd',
          title: 't',
          status: TaskStatus.done,
          createdAt: DateTime.now(),
          notificationId: 1);
      final missed = Task(
          id: 'm',
          title: 't',
          status: TaskStatus.missed,
          createdAt: DateTime.now(),
          notificationId: 1);
      expect(pending.isDone, isFalse);
      expect(done.isDone, isTrue);
      expect(missed.isDone, isFalse);
    });
  });

  group('Task - 枚举完整性', () {
    test('RepeatType / TaskStatus / TaskSource 枚举定义完整', () {
      expect(
        RepeatType.values,
        containsAll([
          RepeatType.none,
          RepeatType.daily,
          RepeatType.weekly,
          RepeatType.weekdays,
          RepeatType.custom,
        ]),
      );
      expect(
        TaskStatus.values,
        containsAll([
          TaskStatus.pending,
          TaskStatus.done,
          TaskStatus.missed,
        ]),
      );
      expect(
        TaskSource.values,
        containsAll([
          TaskSource.manual,
          TaskSource.voice,
        ]),
      );
    });

    test('RepeatType.customWeekdays 语义：1=周一 ... 7=周日', () {
      // 仅校验枚举与自定义星期字段的对应关系（与 TaskCard._repeatLabel 一致）
      final task = Task(
        id: 'w',
        title: 't',
        repeat: RepeatType.custom,
        customWeekdays: const [7],
        createdAt: DateTime.now(),
        notificationId: 1,
      );
      expect(task.customWeekdays, [7]);
    });
  });

  group('Task - Hive 适配器 round-trip', () {
    // 手写适配器最易出错（字段顺序/类型），做一次真实写入-读出校验。
    // 若 headless 环境导致 flaky，可仅保留上面的纯模型测试。
    test('写入再读出字段一致', () async {
      final dir = await Directory.systemTemp.createTemp('hive_task_');
      // Hive 为全局单例，重复 init/register 可能抛错，做保护。
      try {
        Hive.init(dir.path);
      } catch (_) {}
      try {
        Hive.registerAdapter(TaskAdapter());
      } catch (_) {}

      final box = await Hive.openBox<Task>('task_rt_${dir.path.hashCode}');

      final original = Task(
        id: 'rt1',
        title: '适配器回环',
        scheduledTime: DateTime(2026, 7, 14, 15, 30),
        countdownMinutes: 30,
        repeat: RepeatType.custom,
        customWeekdays: const [1, 3, 5],
        status: TaskStatus.done,
        source: TaskSource.voice,
        completedAt: DateTime(2026, 7, 14, 16, 0),
        createdAt: DateTime(2026, 7, 14, 8, 0),
        notificationId: 42,
      );

      await box.put('rt1', original);
      final read = box.get('rt1');

      expect(read, isNotNull, reason: '应能读出写入的任务');
      expect(read!.id, original.id);
      expect(read.title, original.title);
      expect(read.scheduledTime, original.scheduledTime);
      expect(read.countdownMinutes, original.countdownMinutes);
      expect(read.repeat, original.repeat);
      expect(read.customWeekdays, original.customWeekdays);
      expect(read.status, original.status);
      expect(read.source, original.source);
      expect(read.completedAt, original.completedAt);
      expect(read.createdAt, original.createdAt);
      expect(read.notificationId, original.notificationId);

      await box.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
  });

  group('Task - 冲突相关字段（resource/conflictState/effective/durationMinutes）', () {
    test('字段默认值合理', () {
      final t = Task(
        id: 'c0',
        title: '默认',
        createdAt: DateTime(2026, 7, 14),
        notificationId: 1,
      );
      expect(t.resource, isNull);
      expect(t.conflictState, ConflictState.none);
      expect(t.effective, isTrue);
      expect(t.durationMinutes, 0);
      expect(t.hasPendingConflict, isFalse);
      expect(t.isConflictBlocked, isFalse);
    });

    test('冲突字段经 Hive 适配器写入-读出一致', () async {
      final dir = await Directory.systemTemp.createTemp('hive_conflict_');
      try {
        Hive.init(dir.path);
      } catch (_) {}
      try {
        Hive.registerAdapter(TaskAdapter());
      } catch (_) {}

      final box = await Hive.openBox<Task>('conflict_rt_${dir.path.hashCode}');
      final original = Task(
        id: 'cf1',
        title: '占用会议室A',
        scheduledTime: DateTime(2026, 7, 14, 10, 0),
        resource: '会议室A',
        conflictState: ConflictState.pendingConflict,
        effective: false,
        durationMinutes: 90,
        createdAt: DateTime(2026, 7, 14, 8, 0),
        notificationId: 99,
      );
      await box.put('cf1', original);
      final read = box.get('cf1');

      expect(read, isNotNull);
      expect(read!.resource, '会议室A');
      expect(read.conflictState, ConflictState.pendingConflict);
      expect(read.effective, isFalse);
      expect(read.durationMinutes, 90);
      expect(read.hasPendingConflict, isTrue);

      await box.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
  });
}

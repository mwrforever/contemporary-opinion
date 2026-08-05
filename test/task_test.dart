import 'package:daily_planner/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 模型单元测试。
///
/// 覆盖：构造默认值、isRepeating / isDone getter、枚举完整性。
/// （持久化 round-trip 由 task_model_test / task_dao_test 覆盖）
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
  });
}

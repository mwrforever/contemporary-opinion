// 任务筛选口径纯函数测试（V2 状态收敛：全部/进行中/冲突/已完成）
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/theme/task_status_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = DateTime(2026, 8, 1);

  Task make({
    DateTime? at,
    TaskStatus status = TaskStatus.pending,
    ConflictState conflict = ConflictState.none,
    int duration = 0,
    TriggerType? trigger,
    int? maxRepeats,
    int repeatCount = 0,
    RepeatType repeat = RepeatType.none,
    DateTime? createdAt,
  }) =>
      Task(
        id: 't-${DateTime.now().microsecondsSinceEpoch}',
        title: '任务',
        scheduledTime: at,
        status: status,
        conflictState: conflict,
        effective: conflict == ConflictState.none,
        durationMinutes: duration,
        triggerType: trigger,
        maxRepeats: maxRepeats,
        repeatCount: repeatCount,
        repeat: repeat,
        createdAt: createdAt ?? base,
        notificationId: 1,
      );

  group('isInProgressTask - 进行中 Tab 口径', () {
    test('未来待执行、执行窗口内、倒计时重复均命中', () {
      final now = DateTime(2026, 8, 5, 12);
      expect(
        isInProgressTask(
          make(at: now.add(const Duration(hours: 1))),
          now,
        ),
        isTrue,
      );
      expect(
        isInProgressTask(
          make(at: now.subtract(const Duration(minutes: 10)), duration: 60),
          now,
        ),
        isTrue,
      );
      expect(
        isInProgressTask(
          make(
            at: now.add(const Duration(minutes: 30)),
            trigger: TriggerType.delayed,
            maxRepeats: 5,
          ),
          now,
        ),
        isTrue,
      );
    });

    test('冲突任务不进进行中', () {
      final now = DateTime(2026, 8, 5, 12);
      expect(
        isInProgressTask(
          make(
            at: now.add(const Duration(hours: 1)),
            conflict: ConflictState.pendingConflict,
          ),
          now,
        ),
        isFalse,
      );
    });

    test('已过期与已完成不进进行中', () {
      final now = DateTime(2026, 8, 5, 12);
      expect(
        isInProgressTask(
          make(at: now.subtract(const Duration(hours: 3)), duration: 60),
          now,
        ),
        isFalse,
      );
      expect(
        isInProgressTask(make(status: TaskStatus.done), now),
        isFalse,
      );
    });
  });

  group('isDeadDoneTask - 已完成只展示死任务', () {
    test('一次性完成即死任务', () {
      final now = DateTime(2026, 8, 5, 12);
      expect(
        isDeadDoneTask(make(status: TaskStatus.done), now),
        isTrue,
      );
    });

    test('重复任务完成今天不是死任务', () {
      final now = DateTime(2026, 8, 5, 12);
      expect(
        isDeadDoneTask(
          make(status: TaskStatus.done, repeat: RepeatType.daily),
          now,
        ),
        isFalse,
      );
    });

    test('倒计时重复达到上限才死亡', () {
      final now = DateTime(2026, 8, 5, 12);
      expect(
        isDeadDoneTask(
          make(
            status: TaskStatus.done,
            trigger: TriggerType.delayed,
            maxRepeats: 5,
            repeatCount: 4,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        isDeadDoneTask(
          make(
            status: TaskStatus.done,
            trigger: TriggerType.delayed,
            maxRepeats: 5,
            repeatCount: 5,
          ),
          now,
        ),
        isTrue,
      );
    });
  });

  group('isConflictTask / isPastTask', () {
    test('冲突只看 pendingConflict', () {
      expect(
        isConflictTask(make(conflict: ConflictState.pendingConflict)),
        isTrue,
      );
      expect(
        isConflictTask(make(conflict: ConflictState.confirmedOverride)),
        isFalse,
      );
    });

    test('已过期一次性仅在全部置灰展示', () {
      final now = DateTime(2026, 8, 5, 12);
      expect(
        isPastTask(
          make(at: now.subtract(const Duration(hours: 3)), duration: 60),
          now,
        ),
        isTrue,
      );
      expect(
        isPastTask(make(at: now.add(const Duration(hours: 1))), now),
        isFalse,
      );
    });
  });
}

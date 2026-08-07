// resolveVisualState 与筛选口径纯函数测试（V2 状态收敛）
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/theme/task_status_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 5, 12);

  Task make({
    DateTime? at,
    TaskStatus status = TaskStatus.pending,
    ConflictState conflict = ConflictState.none,
    int duration = 0,
    TriggerType? trigger,
    int? maxRepeats,
    int repeatCount = 0,
    RepeatType repeat = RepeatType.none,
  }) =>
      Task(
        id: 't',
        title: 't',
        scheduledTime: at,
        status: status,
        conflictState: conflict,
        effective: conflict == ConflictState.none,
        durationMinutes: duration,
        triggerType: trigger,
        maxRepeats: maxRepeats,
        repeatCount: repeatCount,
        repeat: repeat,
        createdAt: DateTime(2026, 8, 1),
        notificationId: 1,
      );

  test('done 状态优先', () {
    expect(
      resolveVisualState(make(status: TaskStatus.done), now),
      TaskVisualState.done,
    );
  });

  test('冲突待处理 → conflictBlocked（即使时间已过）', () {
    expect(
      resolveVisualState(
        make(at: now.subtract(const Duration(hours: 2)), conflict: ConflictState.pendingConflict),
        now,
      ),
      TaskVisualState.conflictBlocked,
    );
  });

  test('时间待定 → timePending', () {
    expect(
      resolveVisualState(make(conflict: ConflictState.undated), now),
      TaskVisualState.timePending,
    );
  });

  test('无时间 → unscheduled', () {
    expect(resolveVisualState(make(), now), TaskVisualState.unscheduled);
  });

  test('未来时刻 → upcoming', () {
    expect(
      resolveVisualState(make(at: now.add(const Duration(hours: 1))), now),
      TaskVisualState.upcoming,
    );
  });

  test('窗口内 → inProgress', () {
    expect(
      resolveVisualState(
        make(at: now.subtract(const Duration(minutes: 10)), duration: 60),
        now,
      ),
      TaskVisualState.inProgress,
    );
  });

  test('已过期一次性 → past（逾期不再单列）', () {
    expect(
      resolveVisualState(
        make(at: now.subtract(const Duration(hours: 3)), duration: 60),
        now,
      ),
      TaskVisualState.past,
    );
  });

  test('倒计时重复（DELAYED）→ timer', () {
    expect(
      resolveVisualState(
        make(
          at: now.add(const Duration(minutes: 30)),
          trigger: TriggerType.delayed,
          maxRepeats: 5,
        ),
        now,
      ),
      TaskVisualState.timer,
    );
  });

  group('筛选口径（进行中/冲突/已完成）', () {
    test('进行中：未来待执行、执行窗口内、倒计时重复均命中', () {
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

    test('进行中：冲突、已过期、已完成均不命中', () {
      expect(
        isInProgressTask(
          make(conflict: ConflictState.pendingConflict),
          now,
        ),
        isFalse,
      );
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

    test('已完成只展示死任务：一次性完成为死，重复任务完成今天不是死', () {
      expect(
        isDeadDoneTask(make(status: TaskStatus.done), now),
        isTrue,
      );
      expect(
        isDeadDoneTask(
          make(status: TaskStatus.done, repeat: RepeatType.daily),
          now,
        ),
        isFalse,
      );
      // 倒计时重复达到上限后死亡
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

    test('冲突筛选只看冲突状态', () {
      expect(
        isConflictTask(make(conflict: ConflictState.pendingConflict)),
        isTrue,
      );
      expect(isConflictTask(make()), isFalse);
    });

    test('已过期判定', () {
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

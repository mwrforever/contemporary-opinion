// resolveVisualState 纯函数测试（原 task_visual_state_test 的纯逻辑部分）
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
  }) =>
      Task(
        id: 't',
        title: 't',
        scheduledTime: at,
        status: status,
        conflictState: conflict,
        effective: conflict == ConflictState.none,
        durationMinutes: duration,
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

  test('已过期一次性 → overdue', () {
    expect(
      resolveVisualState(
        make(at: now.subtract(const Duration(hours: 3)), duration: 60),
        now,
      ),
      TaskVisualState.overdue,
    );
  });
}

import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/services/conflict_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// 任务合并 / 生效判定测试：覆盖 conflictState / effective 的状态机流转。
void main() {
  final DateTime now = DateTime(2026, 7, 14, 6, 0);

  Task make(String id, DateTime t, {String? resource, int durationMinutes = 60}) => Task(
        id: id,
        title: id,
        scheduledTime: t,
        resource: resource,
        durationMinutes: durationMinutes,
        createdAt: now,
        notificationId: id.hashCode % 2147483647,
      );

  group('applyDecision - 状态机', () {
    test('无冲突 → none / effective=true', () {
      final cand = make('b', DateTime(2026, 7, 14, 14, 0));
      final existing = make('a', DateTime(2026, 7, 14, 8, 0));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      ConflictDetector.applyDecision(cand, r);
      expect(cand.conflictState, ConflictState.none);
      expect(cand.effective, isTrue);
    });

    test('有冲突 → pendingConflict / effective=false（默认不生效）', () {
      final cand = make('b', DateTime(2026, 7, 14, 10, 30), resource: '会议室A');
      final existing = make('a', DateTime(2026, 7, 14, 10, 0), resource: '会议室A');
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      ConflictDetector.applyDecision(cand, r);
      expect(cand.conflictState, ConflictState.pendingConflict);
      expect(cand.effective, isFalse);
    });

    test('改时间消除冲突 → 重检后 none / effective=true', () {
      final cand = make('b', DateTime(2026, 7, 14, 10, 30), resource: '会议室A');
      final existing = make('a', DateTime(2026, 7, 14, 10, 0), resource: '会议室A');
      // 初次：冲突
      ConflictDetector.applyDecision(cand, ConflictDetector.detect(cand, [existing], referenceNow: now));
      expect(cand.effective, isFalse);
      // 用户改时间到 14:00，重检
      cand.scheduledTime = DateTime(2026, 7, 14, 14, 0);
      ConflictDetector.applyDecision(cand, ConflictDetector.detect(cand, [existing], referenceNow: now));
      expect(cand.conflictState, ConflictState.none);
      expect(cand.effective, isTrue);
    });

    test('换资源消除冲突 → 重检后 none / effective=true', () {
      final cand = make('b', DateTime(2026, 7, 14, 10, 30), resource: '会议室A');
      final existing = make('a', DateTime(2026, 7, 14, 10, 0), resource: '会议室A');
      ConflictDetector.applyDecision(cand, ConflictDetector.detect(cand, [existing], referenceNow: now));
      expect(cand.effective, isFalse);
      // 用户换资源为「会议室B」，重检
      cand.resource = '会议室B';
      ConflictDetector.applyDecision(cand, ConflictDetector.detect(cand, [existing], referenceNow: now));
      expect(cand.conflictState, ConflictState.none);
      expect(cand.effective, isTrue);
    });
  });

  group('confirmOverride - 确认覆盖', () {
    test('即便仍冲突也强制生效', () {
      final cand = make('b', DateTime(2026, 7, 14, 10, 30), resource: '会议室A');
      final existing = make('a', DateTime(2026, 7, 14, 10, 0), resource: '会议室A');
      ConflictDetector.applyDecision(cand, ConflictDetector.detect(cand, [existing], referenceNow: now));
      expect(cand.effective, isFalse);
      ConflictDetector.confirmOverride(cand);
      expect(cand.conflictState, ConflictState.confirmedOverride);
      expect(cand.effective, isTrue);
    });
  });

  group('undated - 时间待定', () {
    test('无具体时刻任务 → undated / effective=false', () {
      final cand = Task(
        id: 'b',
        title: 'b',
        scheduledTime: null,
        createdAt: now,
        notificationId: 1,
      );
      final r = ConflictDetector.detect(cand, [], referenceNow: now);
      ConflictDetector.applyDecision(cand, r);
      expect(cand.conflictState, ConflictState.undated);
      expect(cand.effective, isFalse);
    });

    test('补全时刻后重检 → none / effective=true', () {
      final cand = Task(
        id: 'b',
        title: 'b',
        scheduledTime: null,
        createdAt: now,
        notificationId: 1,
      );
      ConflictDetector.applyDecision(
          cand, ConflictDetector.detect(cand, [], referenceNow: now));
      expect(cand.effective, isFalse);
      cand.scheduledTime = DateTime(2026, 7, 14, 14, 0);
      ConflictDetector.applyDecision(
          cand, ConflictDetector.detect(cand, [], referenceNow: now));
      expect(cand.conflictState, ConflictState.none);
      expect(cand.effective, isTrue);
    });
  });

  group('0 时长（只提醒）冲突检测', () {
    test('相同时刻 + 同资源 → 仍判冲突（最小占用宽度兜底）', () {
      final cand = Task(
        id: 'b',
        title: 'b',
        scheduledTime: DateTime(2026, 7, 14, 10, 30),
        resource: '会议室A',
        durationMinutes: 0,
        createdAt: now,
        notificationId: 2,
      );
      final existing = Task(
        id: 'a',
        title: 'a',
        scheduledTime: DateTime(2026, 7, 14, 10, 30),
        resource: '会议室A',
        durationMinutes: 0,
        createdAt: now,
        notificationId: 3,
      );
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      ConflictDetector.applyDecision(cand, r);
      expect(cand.conflictState, ConflictState.pendingConflict);
      expect(cand.effective, isFalse);
    });

    test('相邻时刻（相差 1 分钟）+ 同资源 → 不冲突', () {
      final cand = Task(
        id: 'b',
        title: 'b',
        scheduledTime: DateTime(2026, 7, 14, 10, 31),
        resource: '会议室A',
        durationMinutes: 0,
        createdAt: now,
        notificationId: 2,
      );
      final existing = Task(
        id: 'a',
        title: 'a',
        scheduledTime: DateTime(2026, 7, 14, 10, 30),
        resource: '会议室A',
        durationMinutes: 0,
        createdAt: now,
        notificationId: 3,
      );
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      ConflictDetector.applyDecision(cand, r);
      expect(cand.conflictState, ConflictState.none);
      expect(cand.effective, isTrue);
    });
  });

  group('hasPendingConflict getter', () {
    test('仅 pendingConflict 为真', () {
      final none = make('a', DateTime(2026, 7, 14, 8, 0));
      none.conflictState = ConflictState.none;
      expect(none.hasPendingConflict, isFalse);

      final pend = make('b', DateTime(2026, 7, 14, 8, 0));
      pend.conflictState = ConflictState.pendingConflict;
      expect(pend.hasPendingConflict, isTrue);

      final over = make('c', DateTime(2026, 7, 14, 8, 0));
      over.conflictState = ConflictState.confirmedOverride;
      expect(over.hasPendingConflict, isFalse);
    });
  });
}

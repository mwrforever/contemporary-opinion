import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/services/conflict_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// 冲突检测单元测试（纯 Dart，无 Flutter 依赖）。
///
/// 基准时间 now = 2026-07-14 06:00（周二），候选与已有任务均安排在当天/未来，
/// 全部落在默认 30 天展开窗口内，断言稳定。
void main() {
  final DateTime now = DateTime(2026, 7, 14, 6, 0);

  Task make({
    required String id,
    required String title,
    DateTime? scheduledTime,
    int durationMinutes = 60,
    RepeatType repeat = RepeatType.none,
    List<int> customWeekdays = const [],
    String? resource,
    TaskStatus status = TaskStatus.pending,
  }) =>
      Task(
        id: id,
        title: title,
        scheduledTime: scheduledTime,
        durationMinutes: durationMinutes,
        repeat: repeat,
        customWeekdays: customWeekdays,
        resource: resource,
        status: status,
        createdAt: now,
        notificationId: id.hashCode % 2147483647,
      );

  group('ConflictDetector - 时间重叠', () {
    test('完全相同时间段 → 冲突', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 10, 0));
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 10, 0));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasTimeConflict, isTrue);
      expect(r.hasResourceConflict, isFalse);
    });

    test('部分重叠（候选起点落在已有区间内）→ 冲突', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 9, 0));
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 9, 30));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasTimeConflict, isTrue);
    });

    test('互相包含（候选包含已有）→ 冲突', () {
      final existing = make(id: 'a', title: '短会', scheduledTime: DateTime(2026, 7, 14, 10, 15), durationMinutes: 30);
      final cand = make(id: 'b', title: '长会', scheduledTime: DateTime(2026, 7, 14, 10, 0), durationMinutes: 120);
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasTimeConflict, isTrue);
    });

    test('紧邻不重叠（边界相接）→ 无冲突', () {
      // 已有 09:00-10:00，候选 10:00-11:00（端点相接不算重叠）
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 9, 0));
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 10, 0));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasConflict, isFalse);
    });

    test('不同时段 → 无冲突', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 8, 0));
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 14, 0));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasConflict, isFalse);
    });
  });

  group('ConflictDetector - 资源占用', () {
    test('时间重叠 + 同资源 → 资源占用冲突', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 10, 0), resource: '会议室A');
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 10, 30), resource: '会议室A');
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasTimeConflict, isTrue);
      expect(r.hasResourceConflict, isTrue);
      expect(r.resourceConflicts, contains(existing));
    });

    test('资源名大小写/空格归一化后相等 → 仍判为同资源', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 10, 0), resource: '会议室A');
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 10, 30), resource: ' 会议室a ');
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasResourceConflict, isTrue);
    });

    test('时间重叠但资源不同 → 仅时间冲突，无资源冲突', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 10, 0), resource: '会议室A');
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 10, 30), resource: '会议室B');
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasTimeConflict, isTrue);
      expect(r.hasResourceConflict, isFalse);
    });

    test('同资源但时间不重叠 → 无冲突', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 9, 0), resource: '会议室A');
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 14, 0), resource: '会议室A');
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasConflict, isFalse);
    });

    test('候选无资源 → 即使时间重叠也不产生资源冲突', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 10, 0), resource: '会议室A');
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 10, 30));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasTimeConflict, isTrue);
      expect(r.hasResourceConflict, isFalse);
    });
  });

  group('ConflictDetector - 排除项', () {
    test('已完成(done)任务不占资源 → 无冲突', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 10, 0), resource: '会议室A', status: TaskStatus.done);
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 10, 30), resource: '会议室A');
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasConflict, isFalse);
    });

    test('backlog（无 scheduledTime）已有任务 → 不参与冲突', () {
      final existing = make(id: 'a', title: '待办', scheduledTime: null);
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 10, 30));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasConflict, isFalse);
    });

    test('候选无 scheduledTime → 不参与冲突', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 10, 0));
      final cand = make(id: 'b', title: '待办', scheduledTime: null);
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasConflict, isFalse);
    });
  });

  group('ConflictDetector - 重复任务展开', () {
    test('每日任务与候选次日同时段重叠 → 冲突', () {
      final existing = make(
        id: 'a',
        title: '每日站会',
        scheduledTime: DateTime(2026, 7, 14, 10, 0),
        repeat: RepeatType.daily,
      );
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 15, 10, 30));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasTimeConflict, isTrue, reason: '候选次日 10:30 落在每日任务 10:00-11:00 窗口内');
    });

    test('工作日任务在周六不触发 → 无冲突', () {
      // 2026-07-18 是周六；工作日任务仅周一至周五
      final existing = make(
        id: 'a',
        title: '工作日会',
        scheduledTime: DateTime(2026, 7, 14, 10, 0),
        repeat: RepeatType.weekdays,
      );
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 18, 10, 30));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasConflict, isFalse, reason: '周六不在工作日发生集合内');
    });

    test('自定义星期（周一三五）与候选周一同时段重叠 → 冲突', () {
      // 2026-07-20 是周一
      final existing = make(
        id: 'a',
        title: '周一三五会',
        scheduledTime: DateTime(2026, 7, 14, 10, 0),
        repeat: RepeatType.custom,
        customWeekdays: const [1, 3, 5],
      );
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 20, 10, 30));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.hasTimeConflict, isTrue);
    });
  });

  group('ConflictDetector - 摘要', () {
    test('无冲突返回空串', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 8, 0));
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 14, 0));
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      expect(r.summarize(), isEmpty);
    });

    test('时间+资源冲突返回可读摘要', () {
      final existing = make(id: 'a', title: '开会', scheduledTime: DateTime(2026, 7, 14, 10, 0), resource: '会议室A');
      final cand = make(id: 'b', title: '面试', scheduledTime: DateTime(2026, 7, 14, 10, 30), resource: '会议室A');
      final r = ConflictDetector.detect(cand, [existing], referenceNow: now);
      final s = r.summarize();
      expect(s, contains('时间重叠'));
      expect(s, contains('资源占用'));
      expect(s, contains('「开会」'));
    });
  });
}

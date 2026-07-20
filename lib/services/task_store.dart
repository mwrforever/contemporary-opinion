import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/task.dart';
import 'conflict_detector.dart';

/// 任务仓储：封装 Hive 读写并对外暴露为 ChangeNotifier（Provider）。
class TaskStore extends ChangeNotifier {
  static const String _boxName = 'tasks';
  late Box<Task> _box;

  /// 全部任务，按触发时间升序；无时间的排最后。
  List<Task> get all {
    final list = _box.values.toList();
    list.sort((a, b) {
      final ta = a.scheduledTime;
      final tb = b.scheduledTime;
      if (ta == null && tb == null) return a.createdAt.compareTo(b.createdAt);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
    return list;
  }

  /// 今日任务（按触发时间）。
  List<Task> get today {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return all
        .where((t) =>
            t.scheduledTime != null &&
            t.scheduledTime!.isAfter(start) &&
            t.scheduledTime!.isBefore(end))
        .toList();
  }

  Future<void> init() async {
    _box = await Hive.openBox<Task>(_boxName);
    notifyListeners();
  }

  Task? getById(String id) => _box.get(id);

  Future<void> add(Task task) async {
    await _box.put(task.id, task);
    notifyListeners();
  }

  Future<void> update(Task task) async {
    await task.save();
    notifyListeners();
  }

  Future<void> delete(Task task) async {
    await task.delete();
    notifyListeners();
  }

  /// 切换完成状态。
  ///
  /// 重复任务采用「完成今天这一次」语义：把种子滚动到下一次发生（[Task.nextOccurrence]），
  /// 状态保持 [TaskStatus.pending]，链条留存，**明天仍会提醒**（notifyTaskChanged 走
  /// reschedule 分支）。非重复任务维持原 done/pending 切换。
  Future<void> toggleDone(Task task) => toggleDoneAt(task, DateTime.now());

  /// [toggleDone] 的核心逻辑（可注入 [now]，便于测试）。
  Future<void> toggleDoneAt(Task task, DateTime now) async {
    if (task.isRepeating) {
      // 完成「今天这一次」：种子滚动到「当前发生之后的下一次」（数据保持未来时刻，
      // 干净且通知仍由 matchDateTimeComponents 重发），状态保持 pending；
      // 同时记录 completedAt=now 供视觉层显示「今日已完成」，次日跨日自动恢复。
      final cur = task.nextOccurrence(now);
      if (cur != null) {
        task.scheduledTime =
            task.nextOccurrence(cur.add(Duration(minutes: task.durationMinutes)));
      }
      task.status = TaskStatus.pending;
      task.completedAt = now;
    } else if (task.status == TaskStatus.done) {
      task.status = TaskStatus.pending;
      task.completedAt = null;
    } else {
      task.status = TaskStatus.done;
      task.completedAt = now;
    }
    await task.save();
    notifyListeners();
  }

  /// 标记一次性任务为"已错过"（仅在未完成的过期任务上调用）。
  ///
  /// 重复任务**跳过**：其自身按天/周滚动，不应被标 missed（否则语义混乱且影响排序）。
  Future<void> markMissedIfNeeded() async {
    await markMissedIfNeededAt(DateTime.now());
  }

  /// [markMissedIfNeeded] 的核心逻辑（可注入 [now]，便于测试）。
  Future<void> markMissedIfNeededAt(DateTime now) async {
    var changed = false;
    for (final t in all) {
      if (t.isRepeating) continue; // 重复任务永不被标 missed
      if (t.status == TaskStatus.pending &&
          t.scheduledTime != null &&
          t.scheduledTime!.isBefore(now)) {
        t.status = TaskStatus.missed;
        await t.save();
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// 新增任务并自动做冲突检测：
  /// - 无冲突 → 直接生效（effective=true）
  /// - 有冲突 → 标记 pendingConflict 且默认不生效（effective=false），由界面引导用户手动处理
  Future<void> addWithConflictCheck(Task candidate, {DateTime? now}) async {
    final result =
        ConflictDetector.detect(candidate, all, referenceNow: now);
    ConflictDetector.applyDecision(candidate, result);
    await add(candidate);
  }

  /// 手动改时间/换资源保存后，对"除自身外"的全部任务重检冲突。
  /// 若已无冲突 → 自动恢复生效（none / effective=true）。
  Future<void> recheck(Task task, {DateTime? now}) async {
    final others = all.where((t) => t.id != task.id).toList();
    final result =
        ConflictDetector.detect(task, others, referenceNow: now);
    ConflictDetector.applyDecision(task, result);
    await task.save();
    notifyListeners();
  }

  /// 用户确认覆盖既有冲突任务，强制生效。
  Future<void> resolveOverride(Task task) async {
    ConflictDetector.confirmOverride(task);
    await task.save();
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';

import '../data/daos/task_dao.dart';
import '../models/task.dart';
import 'conflict_detector.dart';

/// 任务仓储：基于 SQLite（TaskDao）并对外暴露为 ChangeNotifier（Provider）。
///
/// [userId] 归属当前登录用户；所有写操作先落库再更新内存并 notifyListeners。
class TaskStore extends ChangeNotifier {
  TaskStore({TaskDao? dao, this.userId = 1}) : _dao = dao ?? TaskDao();

  final TaskDao _dao;
  final int userId;
  List<Task> _tasks = [];

  /// 全部任务，按创建时间降序（新任务在前，冒烟整改口径）。
  List<Task> get all {
    final list = List<Task>.from(_tasks);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

  /// 从数据库加载当前用户任务
  Future<void> init() async {
    _tasks = await _dao.listByUser(userId);
    notifyListeners();
  }

  Task? getById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> add(Task task) async {
    await _dao.insert(task, userId: userId);
    _tasks.add(task);
    notifyListeners();
  }

  Future<void> update(Task task) async {
    await _dao.update(task);
    _replace(task);
  }

  Future<void> delete(Task task) async {
    await _dao.delete(task.id);
    _tasks.removeWhere((t) => t.id == task.id);
    notifyListeners();
  }

  /// 切换完成状态（由提醒引擎播报完成后自动调用；不再提供手动入口）。
  ///
  /// 重复任务采用「完成今天这一次」语义：把种子滚动到下一次发生（[Task.nextOccurrence]），
  /// 状态保持 [TaskStatus.pending]，链条留存，**明天仍会提醒**（notifyTaskChanged 走
  /// reschedule 分支）。非重复任务维持原 done/pending 切换。
  Future<void> toggleDoneAt(Task task, DateTime now) async {
    if (task.isDelayed) {
      // 倒计时重复：完成本次后推进次数；达到上限则任务完成（死任务），否则继续下一次
      task.prevFireTime = task.scheduledTime == null
          ? null
          : task.scheduledTime!.add(
              Duration(seconds: task.intervalSeconds ?? 0) * task.repeatCount);
      task.repeatCount += 1;
      // -1 表示一直重复：完成本次后继续下一次，永不标记完成
      if (task.repeatsForever) {
        task.status = TaskStatus.pending;
        task.completedAt = now;
      } else if (task.maxRepeats != null &&
          task.repeatCount >= task.maxRepeats!) {
        task.status = TaskStatus.done;
        task.completedAt = now;
      } else {
        task.status = TaskStatus.pending;
        task.completedAt = now;
      }
      task.nextFireTime = task.nextFireFor(now);
    } else if (task.isRepeating) {
      // 完成「今天这一次」：种子滚动到下一次发生，状态保持 pending，
      // 记录 completedAt 供视觉层显示「今日已完成」，次日跨日自动恢复。
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
    await _dao.update(task);
    _replace(task);
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
    await _dao.update(task);
    _replace(task);
  }

  /// 用户确认覆盖既有冲突任务，强制生效。
  Future<void> resolveOverride(Task task) async {
    ConflictDetector.confirmOverride(task);
    await _dao.update(task);
    _replace(task);
  }

  /// 用最新实例替换内存中的同名任务并通知监听者
  void _replace(Task task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      _tasks[index] = task;
    } else {
      _tasks.add(task);
    }
    notifyListeners();
  }
}

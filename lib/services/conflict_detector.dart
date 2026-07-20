import '../models/task.dart';

/// 冲突检测结果。
class ConflictResult {
  /// 与候选任务时间重叠的已有任务（无论是否同资源）。
  final List<Task> timeConflicts;

  /// 与候选任务「时间重叠且占用同一资源」的已有任务（资源占用冲突）。
  final List<Task> resourceConflicts;

  const ConflictResult({
    this.timeConflicts = const [],
    this.resourceConflicts = const [],
  });

  bool get hasTimeConflict => timeConflicts.isNotEmpty;
  bool get hasResourceConflict => resourceConflicts.isNotEmpty;

  /// 是否检出任意冲突（含仅时间重叠的弱提醒）。用于"检测完整性"展示。
  bool get hasConflict => hasTimeConflict || hasResourceConflict;

  /// 是否构成「阻断性冲突」——即资源被同一时段重复占用（时间重叠 + 同资源）。
  /// 这是触发标红 / 默认不生效的唯一条件；纯时间重叠（资源不同）视为弱提醒，不阻断。
  bool get hasBlockingConflict => hasResourceConflict;

  /// 人类可读的冲突摘要（用于界面标红提示）。
  String summarize() {
    if (!hasConflict) return '';
    final parts = <String>[];
    if (hasTimeConflict) {
      final names = timeConflicts.map((t) => '「${t.title}」').join('、');
      parts.add('时间重叠：$names');
    }
    if (hasResourceConflict) {
      final names = resourceConflicts.map((t) => '「${t.title}」').join('、');
      parts.add('资源占用：$names');
    }
    return parts.join('；');
  }
}

/// 冲突检测器：时间重叠 + 资源占用。
///
/// 纯 Dart 实现，无 Flutter 依赖，便于单元测试。
/// 设计详见 docs/architecture_aliyun.md §2。
class ConflictDetector {
  /// 默认任务时长（无显式 durationMinutes 时的兜底）。
  static const Duration defaultDuration = Duration(minutes: 60);

  /// 重复任务冲突判定时，向前展开的发生时刻窗口长度。
  static const Duration defaultLookahead = Duration(days: 30);

  /// 检测候选任务与已有任务的冲突。
  ///
  /// - [candidate] 待新增/导入的任务。
  /// - [existing] 已有任务集合（通常来自 TaskStore.all）。
  /// - [referenceNow] 窗口起点，默认 [DateTime.now]（便于测试注入固定时间）。
  /// - [lookahead] 重复任务展开窗口。
  /// - [candidateDuration] 候选任务时长覆盖（不传则用 candidate.durationMinutes）。
  ///
  /// 规则：
  /// 1. 已完成(done)任务不占资源，跳过。
  /// 2. 无 scheduledTime 的 backlog 任务无法定位时段，不参与冲突。
  /// 3. 时段重叠 ⟺ a.start < b.end && b.start < a.end。
  /// 4. 资源占用冲突 ⊂ 时间冲突，且两任务 resource 归一化后相等且非空。
  static ConflictResult detect(
    Task candidate,
    List<Task> existing, {
    DateTime? referenceNow,
    Duration lookahead = defaultLookahead,
    Duration? candidateDuration,
  }) {
    final now = referenceNow ?? DateTime.now();
    final candDur = _effectiveDur(candidateDuration ?? Duration(minutes: candidate.durationMinutes));

    // 无时间任务无法定位时段 → 不参与冲突
    if (candidate.scheduledTime == null) {
      return const ConflictResult();
    }

    final windowEnd = now.add(lookahead);
    final candOcc = _occurrences(candidate, now, windowEnd, candDur);
    if (candOcc.isEmpty) {
      return const ConflictResult();
    }

    final candResource = _normResource(candidate.resource);
    final timeConflicts = <Task>[];
    final resourceConflicts = <Task>[];

    for (final ex in existing) {
      if (ex.status == TaskStatus.done) continue; // 已完成不占资源
      if (ex.scheduledTime == null) continue; // 无法定位时段
      final exDur = _effectiveDur(Duration(minutes: ex.durationMinutes));
      final exOcc = _occurrences(ex, now, windowEnd, exDur);

      var overlaps = false;
      outer:
      for (final c in candOcc) {
        final cEnd = c.add(candDur);
        for (final e in exOcc) {
          final eEnd = e.add(exDur);
          if (c.isBefore(eEnd) && e.isBefore(cEnd)) {
            overlaps = true;
            break outer;
          }
        }
      }

      if (overlaps) {
        timeConflicts.add(ex);
        final exResource = _normResource(ex.resource);
        if (candResource != null && exResource != null && candResource == exResource) {
          resourceConflicts.add(ex);
        }
      }
    }

    return ConflictResult(
      timeConflicts: timeConflicts,
      resourceConflicts: resourceConflicts,
    );
  }

  /// 时长下限：纯提醒任务 durationMinutes=0 是「时刻点」，但冲突检测需要最小占用
  /// 宽度（1 分钟），否则两点永远不重叠、冲突永不被检出。仅用于重叠计算。
  static Duration _effectiveDur(Duration d) =>
      d.inMinutes < 1 ? const Duration(minutes: 1) : d;

  /// 展开任务在 [from, to] 窗口内的所有发生起始时刻。
  /// - 非重复：仅 scheduledTime（若落在窗口内）。
  /// - 重复：按 repeat 类型逐日/逐周生成。
  static List<DateTime> _occurrences(
    Task t,
    DateTime from,
    DateTime to,
    Duration dur,
  ) {
    final base = t.scheduledTime!;
    if (!t.isRepeating) {
      // 窗口定义为 [from - dur, to)，保证「起点在窗口内或与窗口起点重叠」都被纳入
      final windowStart = from.subtract(dur);
      if (base.isBefore(to) && base.isAfter(windowStart)) {
        return [base];
      }
      return const [];
    }

    final results = <DateTime>[];
    // 从 base 当天开始按日步进到 to
    var cursor = DateTime(base.year, base.month, base.day);
    final limit = to.add(const Duration(days: 1));
    while (cursor.isBefore(limit)) {
      final occ = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        base.hour,
        base.minute,
      );
      final inWindow = occ.isBefore(to) && occ.isAfter(from.subtract(dur));
      final matches = switch (t.repeat) {
        RepeatType.daily => true,
        RepeatType.weekdays =>
          occ.weekday >= DateTime.monday && occ.weekday <= DateTime.friday,
        RepeatType.weekly || RepeatType.custom =>
          t.customWeekdays.contains(occ.weekday),
        RepeatType.none => false,
      };
      if (inWindow && matches) results.add(occ);
      cursor = cursor.add(const Duration(days: 1));
    }
    return results;
  }

  /// 资源归一化：空/纯空白 → null；否则去空格小写。
  static String? _normResource(String? r) {
    if (r == null) return null;
    final trimmed = r.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.toLowerCase();
  }

  /// 依据检测结果写回候选任务的冲突状态与生效标记（就地修改 [candidate]）。
  /// 阻断性条件为「资源被同一时段重复占用」([hasBlockingConflict])：
  /// - 资源冲突 → [ConflictState.pendingConflict] / effective=false（默认不生效，等用户手动处理）
  /// - 无资源冲突（含仅时间重叠的弱提醒）→ [ConflictState.none] / effective=true
  ///
  /// 用户后续「确认覆盖」应改调 [confirmOverride]；改时间/换资源后重检应再次调用本方法。
  static void applyDecision(Task candidate, ConflictResult result) {
    // 设定时间的任务未指定具体时刻 → 时间待定异常态：无法参与排期/提醒，
    // 默认不生效，强制用户通过「改时间」补一个时刻后再生效。
    if (candidate.scheduledTime == null) {
      candidate.conflictState = ConflictState.undated;
      candidate.effective = false;
      return;
    }
    if (result.hasBlockingConflict) {
      candidate.conflictState = ConflictState.pendingConflict;
      candidate.effective = false;
    } else {
      candidate.conflictState = ConflictState.none;
      candidate.effective = true;
    }
  }

  /// 用户主动「确认覆盖」：强制生效（即便仍与既有任务重叠）。
  static void confirmOverride(Task candidate) {
    candidate.conflictState = ConflictState.confirmedOverride;
    candidate.effective = true;
  }
}

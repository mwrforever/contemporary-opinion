import 'dart:convert';

/// 重复方式（日历周期重复的 UI 配置，RECURRING 专用）。
enum RepeatType {
  none, // 不重复（一次性）
  daily, // 每天
  weekly, // 每周（在设定的星期几）
  weekdays, // 工作日（周一至周五）
  custom, // 自定义星期几
}

/// 触发类型：一次性 / 日历周期重复 / 相对延时重复。
///
/// 对应统一调度表 task_schedule.trigger_type：
/// - [once]：指定绝对时间触发一次；
/// - [recurring]：按日历周期（天/周/月/年）重复，配置见 [freqType]/[freqInterval]/[endAt]；
/// - [delayed]：按相对延时（[intervalSeconds]）重复 [maxRepeats] 次，进度见 [repeatCount]。
enum TriggerType { once, recurring, delayed }

/// 日历重复频率（RECURRING 专用，对应 task_schedule.freq_type）。
enum FreqType { day, week, month, year }

/// 任务完成状态：仅保留 待执行/已完成。
///
/// 冒烟整改后「待办」「逾期」已收敛移除：过期未处理的一次性任务不再标记 missed，
/// 旧数据中的 missed 在 v3 迁移时统一归为 pending。
enum TaskStatus { pending, done }

/// 来源
enum TaskSource {
  manual, // 手动添加
  voice, // 语音解析生成
}

/// 冲突状态（与冲突检测 + 手动调整生效流程配合）。
enum ConflictState {
  none, // 无冲突，正常生效
  pendingConflict, // 检测到冲突，默认不生效，等待用户手动处理
  confirmedOverride, // 用户已确认覆盖既有任务，强制生效
  undated, // 时间待定：设定时间的任务未指定具体时刻 → 异常态，默认不生效，待用户补时间后生效
}

/// 任务实体（纯 Dart，SQLite 持久化）。
///
/// [id] 为客户端生成的 UUID，对应 tasks 表 TEXT 主键；
/// [toMap]/[fromMap] 负责 snake_case 列映射与枚举/JSON 转换。
///
/// 调度引擎核心字段 [nextFireTime]/[prevFireTime] 供提醒调度与列表状态判定使用；
/// 倒计时重复（DELAYED）任务不再有每天/每月概念，改由
/// [intervalSeconds] × [maxRepeats] + [repeatCount] 描述。
class Task {
  Task({
    required this.id,
    required this.title,
    this.scheduledTime,
    this.countdownMinutes,
    this.countdownSeconds,
    this.repeat = RepeatType.none,
    this.customWeekdays = const [],
    this.status = TaskStatus.pending,
    this.source = TaskSource.manual,
    this.completedAt,
    required this.createdAt,
    required this.notificationId,
    this.resource,
    this.conflictState = ConflictState.none,
    this.effective = true,
    this.durationMinutes = 0,
    this.ringSeconds,
    this.note,
    TriggerType? triggerType,
    FreqType? freqType,
    this.freqInterval = 1,
    this.endAt,
    this.intervalSeconds,
    this.maxRepeats,
    this.repeatCount = 0,
    this.nextFireTime,
    this.prevFireTime,
  })  : // 未显式指定时按旧字段推导：有重复方式即 recurring，否则 once
        triggerType = triggerType ??
            (repeat == RepeatType.none
                ? TriggerType.once
                : TriggerType.recurring),
        // 按旧重复方式推导日历频率（daily→DAY，其余星期类→WEEK）
        freqType = freqType ??
            (repeat == RepeatType.daily
                ? FreqType.day
                : (repeat == RepeatType.none ? null : FreqType.week));

  final String id;
  String title;

  /// 绝对触发时间（倒计时/延时任务在创建时即折算为首次绝对时间）
  DateTime? scheduledTime;

  /// 若由倒计时创建，保留原始分钟数仅用于展示
  final int? countdownMinutes;

  /// 若由倒计时创建，保留原始秒数仅用于展示（秒级倒计时，例如"10秒后"）。
  final int? countdownSeconds;

  RepeatType repeat;

  /// 自定义重复：1=周一 ... 7=周日
  List<int> customWeekdays;

  TaskStatus status;
  TaskSource source;
  final DateTime createdAt;
  DateTime? completedAt;

  /// 通知 id（用于取消）。自定义/工作日会以此为基址派生多个子 id
  final int notificationId;

  /// 所需资源（如「会议室A」「车」「张经理」）。用于资源占用冲突检测；为空表示无特定资源。
  String? resource;

  /// 冲突状态。新建/导入时由 ConflictDetector 写入，详见 docs/architecture_aliyun.md。
  ConflictState conflictState;

  /// 是否真正生效（参与提醒调度）。冲突待处理(pendingConflict)时为 false。
  bool effective;

  /// 任务时长（分钟）。冲突按「时段」而非「时刻」判断；默认 0=仅提醒不占时段。
  int durationMinutes;

  /// 响铃时长（秒）。为 null 时回退到全局默认设置。
  int? ringSeconds;

  /// 备注（语音解析的 note 字段，可选）。
  String? note;

  // ============ 调度引擎字段（对齐 task_schedule） ============

  /// 触发类型：ONCE / RECURRING / DELAYED
  TriggerType triggerType;

  /// 日历重复频率（RECURRING 专用）；once/delayed 为 null
  FreqType? freqType;

  /// 日历重复间隔（如每 2 周 = 2），默认 1
  int freqInterval;

  /// 日历重复结束时间（RECURRING；null 表示无限循环）
  DateTime? endAt;

  /// DELAYED：延时间隔秒数
  int? intervalSeconds;

  /// DELAYED：最大触发次数
  int? maxRepeats;

  /// DELAYED：已触发次数
  int repeatCount;

  /// 下次触发时间（调度引擎核心）
  DateTime? nextFireTime;

  /// 上次触发时间（调度引擎核心）
  DateTime? prevFireTime;

  bool get isRepeating =>
      repeat == RepeatType.daily ||
      repeat == RepeatType.weekly ||
      repeat == RepeatType.weekdays ||
      repeat == RepeatType.custom;

  /// 是否相对延时重复（DELAYED）
  bool get isDelayed => triggerType == TriggerType.delayed;

  /// 是否日历周期重复（RECURRING）
  bool get isRecurring => triggerType == TriggerType.recurring;

  bool get isDone => status == TaskStatus.done;

  /// 是否处于「冲突待处理」状态（标红、未生效）。
  bool get hasPendingConflict => conflictState == ConflictState.pendingConflict;

  /// 是否因冲突而尚未生效（含待处理与理论上可覆盖的情形）。
  bool get isConflictBlocked => conflictState == ConflictState.pendingConflict;

  /// 计算相对 [now] 的下一次触发时间（调度引擎核心，纯函数）。
  ///
  /// - DELAYED：以 [scheduledTime] 为首发，每隔 [intervalSeconds] 触发一次，
  ///   进度由 [repeatCount] 决定；达到 [maxRepeats] 后返回 null（任务死亡）。
  /// - RECURRING：复用 [nextOccurrence] 的滚动锚点语义。
  /// - ONCE：直接返回 [scheduledTime]。
  DateTime? nextFireFor(DateTime now) {
    if (isDelayed) {
      if (maxRepeats != null && repeatCount >= maxRepeats!) return null;
      final base = scheduledTime;
      if (base == null) return null;
      return base.add(Duration(seconds: intervalSeconds ?? 0) * repeatCount);
    }
    if (isRecurring) return nextOccurrence(now);
    return scheduledTime;
  }

  /// 是否「死任务」：已完成且未来不再需要执行（「已完成」Tab 只展示这类任务）。
  bool isDeadDoneAt(DateTime now) => isDone && !_hasFutureOccurrence(now);

  /// 是否仍有未来发生实例（调度层语义）。
  bool _hasFutureOccurrence(DateTime now) {
    if (isDelayed) {
      // 未设上限视为无限循环；否则最后一次触发后即死亡
      return maxRepeats == null || repeatCount < maxRepeats!;
    }
    if (isRecurring) {
      // 周期结束时间已过则不再产生未来实例
      return endAt == null || endAt!.isAfter(now);
    }
    // ONCE：完成即不再执行
    return false;
  }

  /// 计算相对 [now] 的「当前/下一次发生锚点」（RECURRING 任务专用，纯函数）。
  ///
  /// 语义：返回某个发生实例的起始时刻 [S]，使得 [now] 落在窗口 `[S, S+duration)`
  /// 内（即「今天这一次」正在进行），或返回 [now] 之后最近的一个发生起始
  /// （已过期窗口则滚到下次）。该锚点是「滚动」的，永不固定于创建时的种子时刻。
  DateTime? nextOccurrence(DateTime now) {
    final seed = scheduledTime;
    if (seed == null) return null;
    if (repeat == RepeatType.none) return seed;

    final duration = Duration(minutes: durationMinutes);

    if (repeat == RepeatType.daily) {
      // 每天：锚定「今天」的种子时刻；若今天窗口已结束则滚到明天。
      var cand = DateTime(now.year, now.month, now.day, seed.hour, seed.minute);
      if (!cand.add(duration).isAfter(now)) {
        cand = cand.add(const Duration(days: 1));
      }
      return cand;
    }

    // weekly / weekdays / custom：在匹配星期中取「当前/下次」窗口锚点的最小值。
    final weekdays = switch (repeat) {
      RepeatType.weekdays => const [1, 2, 3, 4, 5],
      RepeatType.custom =>
        customWeekdays.isEmpty ? [seed.weekday] : customWeekdays,
      _ => <int>[seed.weekday], // weekly
    };
    DateTime? best;
    for (final w in weekdays) {
      var cand = _occurrenceOnWeekday(now, w);
      if (!cand.add(duration).isAfter(now)) {
        cand = cand.add(const Duration(days: 7));
      }
      if (best == null || cand.isBefore(best)) best = cand;
    }
    return best;
  }

  /// 返回 [ref] 所在周内、星期 [weekday]（1=周一…7=周日）在 [scheduledTime] 时刻的发生起始。
  DateTime _occurrenceOnWeekday(DateTime ref, int weekday) {
    final base = DateTime(
      ref.year,
      ref.month,
      ref.day,
      scheduledTime!.hour,
      scheduledTime!.minute,
    );
    final diff = (weekday - base.weekday) % 7;
    return base.add(Duration(days: diff));
  }

  /// 转 SQLite 行（snake_case；[userId] 非空时附加归属）。
  Map<String, dynamic> toMap({int? userId}) => {
        if (userId != null) 'user_id': userId,
        'id': id,
        'title': title,
        'scheduled_time': scheduledTime?.toIso8601String(),
        'countdown_minutes': countdownMinutes,
        'countdown_seconds': countdownSeconds,
        'repeat': repeat.name,
        'custom_weekdays': jsonEncode(customWeekdays),
        'status': status.name,
        'source': source.name,
        'resource': resource,
        'duration_minutes': durationMinutes,
        'ring_seconds': ringSeconds,
        'conflict_state': conflictState.name,
        'effective': effective ? 1 : 0,
        'notification_id': notificationId,
        'completed_at': completedAt?.toIso8601String(),
        'note': note,
        'created_at': createdAt.toIso8601String(),
        'trigger_type': triggerType.name,
        'freq_type': freqType?.name,
        'freq_interval': freqInterval,
        'end_at': endAt?.toIso8601String(),
        'interval_seconds': intervalSeconds,
        'max_repeats': maxRepeats,
        'repeat_count': repeatCount,
        'next_fire_time': nextFireTime?.toIso8601String(),
        'prev_fire_time': prevFireTime?.toIso8601String(),
      };

  /// 从 SQLite 行还原；缺失/非法枚举回退默认值（兼容旧迁移数据）。
  factory Task.fromMap(Map<String, dynamic> map) {
    final repeat =
        _enumOr(RepeatType.values, map['repeat'], RepeatType.none);
    final triggerRaw = _enumOr(
      TriggerType.values,
      map['trigger_type'],
      repeat == RepeatType.none ? TriggerType.once : TriggerType.recurring,
    );
    return Task(
      id: map['id'] as String,
      title: map['title'] as String,
      scheduledTime: _parseDate(map['scheduled_time']),
      countdownMinutes: map['countdown_minutes'] as int?,
      countdownSeconds: map['countdown_seconds'] as int?,
      repeat: repeat,
      customWeekdays: _parseWeekdays(map['custom_weekdays']),
      status: _enumOr(TaskStatus.values, map['status'], TaskStatus.pending),
      source: _enumOr(TaskSource.values, map['source'], TaskSource.manual),
      createdAt: DateTime.parse(map['created_at'] as String),
      completedAt: _parseDate(map['completed_at']),
      notificationId: map['notification_id'] as int? ?? 0,
      resource: map['resource'] as String?,
      conflictState:
          _enumOr(ConflictState.values, map['conflict_state'], ConflictState.none),
      effective: (map['effective'] as int? ?? 1) == 1,
      durationMinutes: map['duration_minutes'] as int? ?? 0,
      ringSeconds: map['ring_seconds'] as int?,
      note: map['note'] as String?,
      triggerType: triggerRaw,
      freqType: _enumOrNullable(FreqType.values, map['freq_type']),
      freqInterval: map['freq_interval'] as int? ?? 1,
      endAt: _parseDate(map['end_at']),
      intervalSeconds: map['interval_seconds'] as int?,
      maxRepeats: map['max_repeats'] as int?,
      repeatCount: map['repeat_count'] as int? ?? 0,
      nextFireTime: _parseDate(map['next_fire_time']),
      prevFireTime: _parseDate(map['prev_fire_time']),
    );
  }

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);

  static T _enumOr<T extends Enum>(List<T> values, dynamic raw, T fallback) =>
      values.firstWhere((e) => e.name == raw, orElse: () => fallback);

  static T? _enumOrNullable<T extends Enum>(List<T> values, dynamic raw) {
    if (raw == null) return null;
    return values.firstWhere((e) => e.name == raw, orElse: () => values.first);
  }

  static List<int> _parseWeekdays(dynamic raw) {
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw as String) as List).cast<int>();
    } catch (_) {
      return const [];
    }
  }
}

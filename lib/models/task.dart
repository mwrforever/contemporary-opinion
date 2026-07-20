import 'package:hive/hive.dart';

/// 重复方式
enum RepeatType {
  none, // 不重复（一次性）
  daily, // 每天
  weekly, // 每周（在设定的星期几）
  weekdays, // 工作日（周一至周五）
  custom, // 自定义星期几
}

/// 任务完成状态
enum TaskStatus {
  pending, // 待办
  done, // 已完成
  missed, // 已错过（到点未处理的一次性任务）
}

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

/// 任务实体。手写为 Hive 适配器，免去 build_runner 代码生成步骤。
@HiveType(typeId: 0)
class Task extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String title;

  /// 绝对触发时间（倒计时任务在创建时即折算为绝对时间）
  @HiveField(2)
  DateTime? scheduledTime;

  /// 若由倒计时创建，保留原始分钟数仅用于展示
  @HiveField(3)
  final int? countdownMinutes;

  /// 若由倒计时创建，保留原始秒数仅用于展示（秒级倒计时，例如"10秒后"）。
  @HiveField(16)
  final int? countdownSeconds;

  @HiveField(4)
  RepeatType repeat;

  /// 自定义重复：1=周一 ... 7=周日
  @HiveField(5)
  List<int> customWeekdays;

  @HiveField(6)
  TaskStatus status;

  @HiveField(7)
  TaskSource source;

  @HiveField(8)
  final DateTime createdAt;

  @HiveField(9)
  DateTime? completedAt;

  /// 通知 id（用于取消）。自定义/工作日会以此为基址派生多个子 id
  @HiveField(10)
  final int notificationId;

  /// 所需资源（如「会议室A」「车」「张经理」）。用于资源占用冲突检测；为空表示无特定资源。
  @HiveField(11)
  String? resource;

  /// 冲突状态。新建/导入时由 ConflictDetector 写入，详见 docs/architecture_aliyun.md。
  @HiveField(12)
  ConflictState conflictState;

  /// 是否真正生效（参与提醒调度）。冲突待处理(pendingConflict)时为 false。
  @HiveField(13)
  bool effective;

  /// 任务时长（分钟）。冲突按「时段」而非「时刻」判断；默认 60 分钟。
  @HiveField(14)
  int durationMinutes;

  /// 响铃时长（秒）。为 null 时回退到全局默认设置。
  @HiveField(15)
  int? ringSeconds;

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
  });

  bool get isRepeating =>
      repeat == RepeatType.daily ||
      repeat == RepeatType.weekly ||
      repeat == RepeatType.weekdays ||
      repeat == RepeatType.custom;

  bool get isDone => status == TaskStatus.done;

  /// 是否处于「冲突待处理」状态（标红、未生效）。
  bool get hasPendingConflict => conflictState == ConflictState.pendingConflict;

  /// 是否因冲突而尚未生效（含待处理与理论上可覆盖的情形）。
  bool get isConflictBlocked => conflictState == ConflictState.pendingConflict;

  /// 计算相对 [now] 的「当前/下一次发生锚点」（重复任务专用，纯函数）。
  ///
  /// 语义：返回某个发生实例的起始时刻 [S]，使得 [now] 落在窗口 `[S, S+duration)`
  /// 内（即「今天这一次」正在进行），或返回 [now] 之后最近的一个发生起始
  /// （已过期窗口则滚到下次）。该锚点是「滚动」的，永不固定于创建时的种子时刻。
  ///
  /// - [RepeatType.none]：不滚动，直接返回 [scheduledTime]。
  /// - [RepeatType.daily]：锚定「今天」种子时刻；若今天窗口已过则滚到明天。
  /// - [RepeatType.weekly] / [weekdays] / [custom]：在匹配星期中取当前/下次窗口锚点
  ///   的最小值（weekdays 限周一~五，custom 用 [customWeekdays]，weekly 用种子星期几）。
  /// - [scheduledTime] 为 null：返回 null。
  ///
  /// 用途：
  ///  1. [resolveVisualState] 判定重复任务视觉状态（永不判 overdue，窗口内 inProgress）。
  ///  2. [TaskStore.toggleDone] 完成「今天这一次」后把种子滚动到下一次发生。
  ///
  /// 纯函数：不依赖 [ReminderService]（避免 import 环），仅消费自身字段。
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
  ///
  /// [scheduledTime] 已在上层判空，此处安全使用 `!`。
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
}

/// 手写 TypeAdapter（枚举以 int 存储，规避枚举适配器依赖）
class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 0;

  @override
  Task read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Task(
      id: fields[0] as String,
      title: fields[1] as String,
      scheduledTime: fields[2] as DateTime?,
      countdownMinutes: fields[3] as int?,
      countdownSeconds: fields[16] as int?,
      repeat: RepeatType.values[(fields[4] as int? ?? 0)],
      customWeekdays: (fields[5] as List?)?.cast<int>() ?? const [],
      status: TaskStatus.values[(fields[6] as int? ?? 0)],
      source: TaskSource.values[(fields[7] as int? ?? 0)],
      createdAt: fields[8] as DateTime,
      completedAt: fields[9] as DateTime?,
      notificationId: fields[10] as int,
      resource: fields[11] as String?,
      conflictState: ConflictState.values[(fields[12] as int? ?? 0)],
      effective: fields[13] as bool? ?? true,
      durationMinutes: fields[14] as int? ?? 0,
      ringSeconds: fields[15] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.scheduledTime)
      ..writeByte(3)
      ..write(obj.countdownMinutes)
      ..writeByte(4)
      ..write(obj.repeat.index)
      ..writeByte(5)
      ..write(obj.customWeekdays)
      ..writeByte(6)
      ..write(obj.status.index)
      ..writeByte(7)
      ..write(obj.source.index)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.completedAt)
      ..writeByte(10)
      ..write(obj.notificationId)
      ..writeByte(11)
      ..write(obj.resource)
      ..writeByte(12)
      ..write(obj.conflictState.index)
      ..writeByte(13)
      ..write(obj.effective)
      ..writeByte(14)
      ..write(obj.durationMinutes)
      ..writeByte(15)
      ..write(obj.ringSeconds)
      ..writeByte(16)
      ..write(obj.countdownSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskAdapter && other.typeId == typeId;
}

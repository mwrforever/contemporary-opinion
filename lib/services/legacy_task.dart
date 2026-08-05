import 'package:hive_ce/hive_ce.dart';

/// 旧版任务冻结模型：仅在「Hive → SQLite 迁移」场景使用。
///
/// 与旧版 `Task`（@HiveType(0) + 手写 TaskAdapter）的二进制布局完全一致，
/// 保证升级后仍能解码历史数据；不随新 Task 模型演进。
class LegacyTask {
  const LegacyTask({
    required this.id,
    required this.title,
    this.scheduledTime,
    this.countdownMinutes,
    this.countdownSeconds,
    required this.repeatIndex,
    this.customWeekdays = const [],
    required this.statusIndex,
    required this.sourceIndex,
    required this.createdAt,
    this.completedAt,
    required this.notificationId,
    this.resource,
    required this.conflictStateIndex,
    this.effective = true,
    this.durationMinutes = 0,
    this.ringSeconds,
  });

  final String id;
  final String title;
  final DateTime? scheduledTime;
  final int? countdownMinutes;
  final int? countdownSeconds;
  final int repeatIndex; // 0 none / 1 daily / 2 weekly / 3 weekdays / 4 custom
  final List<int> customWeekdays;
  final int statusIndex; // 0 pending / 1 done / 2 missed
  final int sourceIndex; // 0 manual / 1 voice
  final DateTime createdAt;
  final DateTime? completedAt;
  final int notificationId;
  final String? resource;
  final int conflictStateIndex; // 0 none / 1 pendingConflict / 2 confirmedOverride / 3 undated
  final bool effective;
  final int durationMinutes;
  final int? ringSeconds;
}

/// 旧版 Task 的 TypeAdapter（typeId 0）：与旧实现字段顺序完全一致。
class LegacyTaskAdapter extends TypeAdapter<LegacyTask> {
  @override
  final int typeId = 0;

  @override
  LegacyTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LegacyTask(
      id: fields[0] as String,
      title: fields[1] as String,
      scheduledTime: fields[2] as DateTime?,
      countdownMinutes: fields[3] as int?,
      countdownSeconds: fields[16] as int?,
      repeatIndex: fields[4] as int? ?? 0,
      customWeekdays: (fields[5] as List?)?.cast<int>() ?? const [],
      statusIndex: fields[6] as int? ?? 0,
      sourceIndex: fields[7] as int? ?? 0,
      createdAt: fields[8] as DateTime,
      completedAt: fields[9] as DateTime?,
      notificationId: fields[10] as int,
      resource: fields[11] as String?,
      conflictStateIndex: fields[12] as int? ?? 0,
      effective: fields[13] as bool? ?? true,
      durationMinutes: fields[14] as int? ?? 0,
      ringSeconds: fields[15] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, LegacyTask obj) {
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
      ..write(obj.repeatIndex)
      ..writeByte(5)
      ..write(obj.customWeekdays)
      ..writeByte(6)
      ..write(obj.statusIndex)
      ..writeByte(7)
      ..write(obj.sourceIndex)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.completedAt)
      ..writeByte(10)
      ..write(obj.notificationId)
      ..writeByte(11)
      ..write(obj.resource)
      ..writeByte(12)
      ..write(obj.conflictStateIndex)
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
      other is LegacyTaskAdapter && other.typeId == typeId;
}

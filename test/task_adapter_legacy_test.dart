import 'dart:io';

import 'package:hive/hive.dart';
import 'package:daily_planner/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// 旧数据（升级前 T1 之前）兼容性测试。
///
/// 模拟旧版适配器：只写 16 个字段（无 [countdownSeconds] 字段 16）。
/// 其 `read` 直接委托给当前 [TaskAdapter.read]，从而验证：
/// 「只含 16 字段的旧数据」被新适配器读出时，[countdownSeconds] 为 null、不崩溃，
/// 且其余字段保持完整。
///
/// 重要：[Task] 是 [HiveObject]，`box.get` 默认返回缓存的「活实例」而非重新解码，
/// 因此本测试在写入后 **关闭并重新打开盒子**，强制从磁盘解码，真正走 [TaskAdapter.read]。
///
/// 注：本文件与 `task_adapter_test.dart` 各自注册 typeId=0 的适配器，
/// 需分文件隔离（Hive 为全局单例），故独立成文件。
class LegacyTaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 0;

  @override
  Task read(BinaryReader reader) => TaskAdapter().read(reader);

  @override
  void write(BinaryWriter writer, Task obj) {
    // 旧格式：writeByte(16) + 字段 0..15，故意不含字段 16（countdownSeconds）。
    writer
      ..writeByte(16)
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
      ..write(obj.ringSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacyTaskAdapter && other.typeId == typeId;
}

void main() {
  late Directory tmp;
  late Box box;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('hive_legacy_');
    try {
      Hive.init(tmp.path);
    } catch (_) {}
    try {
      Hive.registerAdapter(LegacyTaskAdapter());
    } catch (_) {}
  });

  setUp(() async {
    box = await Hive.openBox('task_adapter_legacy');
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  /// 写入后关闭并重新打开盒子，迫使从磁盘解码（走真实 read 路径）。
  Future<Task?> _putAndReopenDecode(String key, Task old) async {
    await box.put(key, old); // 经 LegacyTaskAdapter 写出 16 字段
    await box.close();
    box = await Hive.openBox('task_adapter_legacy');
    return box.get(key) as Task?;
  }

  test('旧 16 字段数据被新版适配器读出：countdownSeconds=null 且不崩溃', () async {
    final old = Task(
      id: 'l1',
      title: '升级前的旧任务',
      countdownSeconds: 10, // 旧适配器会忽略此字段
      createdAt: DateTime(2026, 7, 14, 9, 0),
      notificationId: 1,
    );
    final read = await _putAndReopenDecode('l1', old);

    expect(read, isNotNull, reason: '旧数据应能正常解码');
    expect(read!.title, '升级前的旧任务');
    expect(read.notificationId, 1);
    expect(read.countdownSeconds, isNull,
        reason: '旧数据无字段 16，应读为 null 而非崩溃');
  });

  test('旧数据其余字段（重复/状态/资源）保持完整', () async {
    final old = Task(
      id: 'l2',
      title: '占用会议室A',
      repeat: RepeatType.weekly,
      resource: '会议室A',
      conflictState: ConflictState.pendingConflict,
      effective: false,
      durationMinutes: 90,
      createdAt: DateTime(2026, 7, 14, 9, 0),
      notificationId: 7,
    );
    final read = await _putAndReopenDecode('l2', old);

    expect(read, isNotNull);
    expect(read!.repeat, RepeatType.weekly);
    expect(read.resource, '会议室A');
    expect(read.conflictState, ConflictState.pendingConflict);
    expect(read.effective, false);
    expect(read.durationMinutes, 90);
    expect(read.countdownSeconds, isNull);
  });
}

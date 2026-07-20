import 'dart:io';

import 'package:hive/hive.dart';
import 'package:daily_planner/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// TaskAdapter 倒计时字段（T1，HiveField 16）单元测试。
///
/// 验证：
///  1. 含 [countdownSeconds] 的 Task 经手写适配器写入-读出 round-trip 一致（字段 16 对齐）。
///  2. [countdownSeconds] 与 [countdownMinutes] 共存时互不污染。
///  3. 新格式下 countdownSeconds 为 null 也能正确读出（不崩溃）。
///
/// 旧 16 字段数据（升级前、无字段 16）的兼容性见同目录 `task_adapter_legacy_test.dart`。
void main() {
  late Directory tmp;
  late Box<Task> box;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('hive_adapter_');
    // Hive 为全局单例，重复 init / 注册可能抛错，做保护。
    try {
      Hive.init(tmp.path);
    } catch (_) {}
    try {
      Hive.registerAdapter(TaskAdapter());
    } catch (_) {}
    box = await Hive.openBox<Task>('task_adapter_test');
  });

  setUp(() async {
    await box.clear();
  });

  tearDownAll(() async {
    await box.close();
    await Hive.deleteFromDisk();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('round-trip：含 countdownSeconds 的 Task 写回一致（字段 16 对齐）', () async {
    final original = Task(
      id: 'a1',
      title: '10秒后倒垃圾',
      scheduledTime: DateTime(2026, 7, 14, 10, 0),
      countdownSeconds: 10,
      createdAt: DateTime(2026, 7, 14, 9, 0),
      notificationId: 1,
    );
    await box.put('a1', original);
    final read = box.get('a1');

    expect(read, isNotNull, reason: '应能读出写入的任务');
    expect(read!.countdownSeconds, 10, reason: '字段 16 应正确 round-trip');
    expect(read.title, '10秒后倒垃圾');
    expect(read.scheduledTime, DateTime(2026, 7, 14, 10, 0));
  });

  test('countdownSeconds 与 countdownMinutes 共存互不污染', () async {
    final original = Task(
      id: 'a3',
      title: '混合倒计时',
      countdownMinutes: 5,
      countdownSeconds: 30,
      createdAt: DateTime(2026, 7, 14, 9, 0),
      notificationId: 3,
    );
    await box.put('a3', original);
    final read = box.get('a3')!;

    expect(read.countdownSeconds, 30, reason: '秒级不应被分钟覆盖');
    expect(read.countdownMinutes, 5, reason: '分钟不应被秒级覆盖');
  });

  test('新格式（字段 16 存在但为 null）读回为 null 且不报错', () async {
    final original = Task(
      id: 'a2',
      title: '普通任务',
      countdownMinutes: 20,
      createdAt: DateTime(2026, 7, 14, 9, 0),
      notificationId: 2,
    );
    // 构造时未传 countdownSeconds（即 null），适配器仍写出 17 字段（字段 16 = null）。
    await box.put('a2', original);
    final read = box.get('a2')!;

    expect(read.countdownSeconds, isNull, reason: '未设置秒级时应为 null');
    expect(read.countdownMinutes, 20);
  });
}

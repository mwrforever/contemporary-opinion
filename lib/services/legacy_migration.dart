import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../data/database_helper.dart';
import 'legacy_task.dart';

/// 旧版 Hive → SQLite 尽力迁移服务。
///
/// 读取旧版 `tasks` Hive box（[LegacyTask] 冻结格式），逐条写入 SQLite tasks 表，
/// 归属 [userId]（升级后首个注册用户通常为 id=1）。
/// 幂等：完成后在 Hive `app_meta` box 写 `legacy_migrated=true`；
/// 任一环节异常只记录日志、静默跳过，不阻塞登录。
/// 记事本旧数据待阶段 3 建表后另行迁移。
class LegacyMigrationService {
  static const _tasksBoxName = 'tasks';
  static const _metaBoxName = 'app_meta';
  static const _migratedKey = 'legacy_migrated';

  // 枚举名（与旧 Task 模型一致，避免依赖新模型演进）
  static const _repeatNames = ['none', 'daily', 'weekly', 'weekdays', 'custom'];
  static const _statusNames = ['pending', 'done', 'missed'];
  static const _sourceNames = ['manual', 'voice'];
  static const _conflictNames = [
    'none',
    'pendingConflict',
    'confirmedOverride',
    'undated',
  ];

  /// 执行迁移；返回是否写入过数据。失败静默返回 false。
  Future<bool> migrate({required int userId}) async {
    try {
      // 生产环境初始化 Hive 文档目录；单元测试已 Hive.init(tempDir) 时
      // path_provider 不可用会抛错，捕获后继续使用已初始化实例
      try {
        await Hive.initFlutter();
      } catch (e) {
        debugPrint('Hive.initFlutter 不可用，沿用既有初始化: $e');
      }
      if (!Hive.isAdapterRegistered(LegacyTaskAdapter().typeId)) {
        Hive.registerAdapter(LegacyTaskAdapter());
      }
      if (await _isMigrated()) return false;

      final box = await Hive.openBox<LegacyTask>(_tasksBoxName);
      final tasks = box.values.whereType<LegacyTask>().toList();
      if (tasks.isEmpty) {
        await _markMigrated();
        return false;
      }

      final db = await DatabaseHelper.instance.database;
      for (final task in tasks) {
        try {
          await db.insert('tasks', _toRow(task, userId));
        } catch (e) {
          // 单条损坏不中断整体迁移
          debugPrint('旧任务迁移单条失败: $e');
        }
      }
      await _markMigrated();
      return true;
    } catch (e) {
      debugPrint('旧数据迁移跳过（Hive 不可用或格式变化）: $e');
      return false;
    }
  }

  Future<bool> _isMigrated() async {
    final meta = await Hive.openBox(_metaBoxName);
    return meta.get(_migratedKey, defaultValue: false) == true;
  }

  Future<void> _markMigrated() async {
    final meta = await Hive.openBox(_metaBoxName);
    await meta.put(_migratedKey, true);
  }

  /// 旧模型字段 → SQLite 行（snake_case + JSON 星期）
  Map<String, dynamic> _toRow(LegacyTask t, int userId) => {
        'user_id': userId,
        'title': t.title,
        'scheduled_time': t.scheduledTime?.toIso8601String(),
        'countdown_minutes': t.countdownMinutes,
        'countdown_seconds': t.countdownSeconds,
        'repeat': _repeatNames[t.repeatIndex],
        'custom_weekdays': jsonEncode(t.customWeekdays),
        'status': _statusNames[t.statusIndex],
        'source': _sourceNames[t.sourceIndex],
        'resource': t.resource,
        'duration_minutes': t.durationMinutes,
        'ring_seconds': t.ringSeconds,
        'conflict_state': _conflictNames[t.conflictStateIndex],
        'effective': t.effective ? 1 : 0,
        'notification_id': t.notificationId,
        'completed_at': t.completedAt?.toIso8601String(),
        'note': null,
        'created_at': t.createdAt.toIso8601String(),
      };
}

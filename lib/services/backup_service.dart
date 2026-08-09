import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

import '../data/daos/task_dao.dart';
import '../data/daos/user_dao.dart';
import '../models/task.dart';

/// JSON 备份服务：导出/导入本地数据（不含任何密码哈希）。
///
/// [exportJson]/[importJson] 为纯逻辑可单测；
/// [shareExport]/[pickImportFile] 封装系统分享与文件选择（平台插件）。
class BackupService {
  BackupService({TaskDao? taskDao, UserDao? userDao})
      : _taskDao = taskDao ?? TaskDao(),
        _userDao = userDao ?? UserDao();

  final TaskDao _taskDao;
  final UserDao _userDao;

  /// 导出指定用户的备份 JSON：任务 + 个人偏好（不含 password_hash）
  Future<String> exportJson(int userId) async {
    final tasks = await _taskDao.listByUser(userId);
    final user = await _userDao.findById(userId);
    return jsonEncode({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'user': user == null
          ? null
          : {
              'username': user.username,
              'nickname': user.nickname,
              'default_ring_seconds': user.defaultRingSeconds,
            },
      'tasks': [for (final t in tasks) t.toMap()],
    });
  }

  /// 通过系统分享导出 JSON 文件
  Future<void> shareExport(String fileName, String json) async {
    await Share.shareXFiles([
      XFile.fromData(
        utf8.encode(json),
        mimeType: 'application/json',
        name: fileName,
      ),
    ]);
  }

  /// 让用户选择 JSON 备份文件；取消返回 null
  Future<String?> pickImportFile() async {
    const typeGroup = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return null;
    return file.readAsString();
  }

  /// 导入备份：返回成功导入的任务条数；格式非法抛中文异常。
  ///
  /// 单条损坏数据跳过不中断；不覆盖同名任务（id 冲突时静默失败）。
  Future<int> importJson(int userId, String json) async {
    validateImport(json); // 格式校验与导入逻辑共用同一判定
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    var count = 0;
    for (final item in decoded['tasks'] as List) {
      if (item is! Map) continue;
      try {
        final task = Task.fromMap(Map<String, dynamic>.from(item));
        await _taskDao.insert(task, userId: userId);
        count++;
      } catch (_) {
        // 单条损坏跳过，不影响其余导入
      }
    }
    return count;
  }

  /// 校验备份 JSON 格式并返回其中的任务条数（不写库）。
  ///
  /// 用于导入前的确认弹窗：格式非法抛中文异常，合法时供 UI 展示条数。
  /// 校验规则与 [importJson] 完全一致，避免「确认后可导入」与
  /// 「实际导入」出现口径分歧。
  int validateImport(String json) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw const FormatException('备份文件不是有效 JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['tasks'] is! List) {
      throw const FormatException('备份文件格式不正确');
    }
    return (decoded['tasks'] as List).length;
  }
}

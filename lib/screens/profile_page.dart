import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/user.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/reminder_service.dart';
import 'login_page.dart';
import 'permission_guide_screen.dart';

/// 我的页：用户信息、默认响铃、JSON 备份、提醒设置、退出登录。
///
/// 备份导出/导入走 [BackupService]（分享/文件选择为平台插件，异常就地提示）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.auth,
    this.backup,
    this.reminder,
  });

  final AuthService auth;
  final BackupService? backup;
  final ReminderService? reminder;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final BackupService _backup = widget.backup ?? BackupService();
  late final ReminderService _reminder =
      widget.reminder ?? ReminderService();

  Future<void> _editNickname(User user) async {
    final controller = TextEditingController(text: user.nickname ?? '');
    final nickname = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑昵称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (nickname == null || !mounted) return;
    await widget.auth.updateProfile(nickname: nickname);
    setState(() {});
  }

  Future<void> _editRing(User user) async {
    final controller = TextEditingController(
      text: user.defaultRingSeconds?.toString() ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('默认响铃时长'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '秒',
            helperText: '新建任务未指定响铃时使用',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    await widget.auth.updateProfile(defaultRingSeconds: int.tryParse(value));
    setState(() {});
  }

  Future<void> _export(User user) async {
    try {
      final json = await _backup.exportJson(user.id!);
      final name =
          'daily_planner_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      await _backup.shareExport(name, json);
      _toast('备份已生成，请保存到安全位置');
    } catch (_) {
      _toast('导出失败');
    }
  }

  Future<void> _import(User user) async {
    try {
      final text = await _backup.pickImportFile();
      if (text == null) return; // 用户取消
      final count = await _backup.importJson(user.id!, text);
      _toast('已导入 $count 条任务');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('导入失败');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _logout() async {
    await widget.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: FutureBuilder<User?>(
        future: widget.auth.currentUser(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final displayName =
              user.nickname?.isNotEmpty == true ? user.nickname! : user.username;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    child: Text(
                      displayName.characters.first,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '@${user.username} · 本地账户',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _row(
                icon: Icons.person_outline,
                label: '编辑昵称',
                onTap: () => _editNickname(user),
              ),
              _row(
                icon: Icons.alarm,
                label: '默认响铃时长',
                trailing: user.defaultRingSeconds == null
                    ? '未设置'
                    : '${user.defaultRingSeconds} 秒',
                onTap: () => _editRing(user),
              ),
              _row(
                icon: Icons.file_upload_outlined,
                label: '导出数据',
                trailing: 'JSON 备份',
                onTap: () => _export(user),
              ),
              _row(
                icon: Icons.file_download_outlined,
                label: '导入数据',
                trailing: '恢复备份',
                onTap: () => _import(user),
              ),
              _row(
                icon: Icons.notifications_outlined,
                label: '提醒设置',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PermissionGuideScreen(reminder: _reminder),
                  ),
                ),
              ),
              _row(
                icon: Icons.dark_mode_outlined,
                label: '深色模式',
                trailing: '跟随系统',
              ),
              _row(
                icon: Icons.info_outline,
                label: '关于时说',
                trailing: 'v1.0.0',
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onPressed: _logout,
                  child: const Text('退出登录'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    String? trailing,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (onTap != null)
            const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}

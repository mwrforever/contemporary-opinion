import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/reminder_service.dart';

/// 提醒权限引导页：通知权限 / 电池优化 / 自启动三项清单。
///
/// 「去开启」触发权限请求并尝试跳转系统设置（不可用时静默）。
class PermissionGuideScreen extends StatelessWidget {
  const PermissionGuideScreen({super.key, this.reminder});

  final ReminderService? reminder;

  Future<void> _openSettings(BuildContext context) async {
    try {
      await (reminder ?? ReminderService()).ensurePermissions();
    } catch (_) {}
    try {
      await launchUrl(
        Uri.parse('app-settings:'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // 无系统设置入口时忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Icon(Icons.notifications_active_outlined,
                size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              '开启提醒，日程不迟到',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '需要通知与后台调度权限，应用被关闭也能准时提醒。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _checkItem(context, '通知权限', '允许系统弹提醒与响铃'),
            _checkItem(context, '电池优化', '允许后台运行，避免杀进程'),
            _checkItem(context, '开机自启动', '部分机型需手动放行'),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () => _openSettings(context),
                  child: const Text('去开启'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('稍后再说'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkItem(BuildContext context, String title, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(Icons.check_circle_outline, color: scheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

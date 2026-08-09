import 'package:flutter/material.dart';

import '../services/permission_status_service.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';

/// 提醒权限引导页：仅通知权限清单。
///
/// 电池优化与开机自启动因多数机型无法可靠设置/检测（自启动无通用 API），
/// 已按要求从设置中移除；此处实时回显通知权限「已开启 / 待处理」，
/// 从系统设置返回（AppLifecycleState.resumed）自动刷新；授权后主按钮
/// 变为「已完成」禁用态。
///
/// 依赖 [PermissionStatusService]（状态聚合）与 [ReminderService]（通知请求）；
/// 系统请求/跳转动作可注入替身，便于 widget 测试。
class PermissionGuideScreen extends StatefulWidget {
  const PermissionGuideScreen({
    super.key,
    this.reminder,
    this.permissionStatus,
    this.onRequestNotification,
  });

  final ReminderService? reminder;
  final PermissionStatusService? permissionStatus;

  /// 测试注入：请求通知权限（默认走 [ReminderService.ensurePermissions]）
  final Future<void> Function()? onRequestNotification;

  @override
  State<PermissionGuideScreen> createState() => _PermissionGuideScreenState();
}

class _PermissionGuideScreenState extends State<PermissionGuideScreen>
    with WidgetsBindingObserver {
  late final ReminderService _reminder = widget.reminder ?? ReminderService();
  late final PermissionStatusService _permissionStatus =
      widget.permissionStatus ?? PermissionStatusService();

  /// 当前权限聚合状态；加载前为 null。
  ReminderPermissionStatus? _status;

  @override
  void initState() {
    super.initState();
    // 监听前后台切换：从系统设置返回时自动刷新
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 系统设置页返回前台时重新检测权限
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// 重新检测三项权限状态并刷新 UI。
  Future<void> _refresh() async {
    final status = await _permissionStatus.reminderStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  /// 请求通知权限（含精确闹钟），随后刷新状态。
  Future<void> _requestNotification() async {
    final request = widget.onRequestNotification;
    if (request != null) {
      await request();
    } else {
      try {
        await _reminder.ensurePermissions();
      } catch (_) {
        // 权限请求失败静默，由状态回显反馈
      }
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    final allGranted = status?.granted ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // 头部：图标 + 标题 + 说明
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.notifications_active_outlined,
                size: 36,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '开启提醒，日程不迟到',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '需要通知与后台调度权限，应用被关闭也能准时提醒。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          // 通知权限清单：实时回显状态
          _permCard(
            icon: Icons.notifications_active_outlined,
            name: '通知权限',
            desc: '允许系统弹提醒与响铃',
            granted: status?.notification ?? false,
            onTap: () {
              if (status?.notification ?? false) return;
              _requestNotification();
            },
          ),
          const SizedBox(height: 14),
          // 实时刷新说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '权限状态实时检测：从系统设置返回本页自动刷新；'
                    '电池优化与开机自启动因无法可靠设置已移除。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 主操作：全开后变「已完成」禁用态
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: allGranted ? null : _goEnable,
              child: Text(allGranted ? '已完成' : '去开启'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(allGranted ? '完成' : '稍后再说'),
            ),
          ),
        ],
      ),
    );
  }

  /// 主按钮「去开启」：请求通知权限。
  Future<void> _goEnable() async {
    await _requestNotification();
  }

  /// 单项权限卡片：状态图标 + 名称 + 说明 + 已开启/待处理徽标。
  Widget _permCard({
    required IconData icon,
    required String name,
    required String desc,
    required bool granted,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = isDark ? AppTheme.okDark : AppTheme.ok;
    final okSoft = isDark ? const Color(0xFF1C3326) : AppTheme.okSoft;
    final warn = isDark ? AppTheme.warnDark : AppTheme.warn;
    final warnSoft = isDark ? const Color(0xFF3A2C1A) : AppTheme.warnSoft;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: granted ? okSoft : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: granted ? ok : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: granted ? okSoft : warnSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (granted)
                      Icon(Icons.check, size: 12, color: ok)
                    else
                      Icon(Icons.schedule, size: 12, color: warn),
                    const SizedBox(width: 4),
                    Text(
                      granted ? '已开启' : '待处理',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: granted ? ok : warn,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:permission_handler/permission_handler.dart';

/// 提醒权限状态：通知权限（任务提醒与任务模块的前置条件）。
///
/// 电池优化与开机自启动此前并入引导页，但二者在多数机型无法可靠设置/
/// 检测（自启动无通用 API），已从设置中移除，仅保留可真实设置的通知权限。
class ReminderPermissionStatus {
  const ReminderPermissionStatus({required this.notification});

  /// 通知权限是否已授权
  final bool notification;

  /// 通知权限是否已开启。
  bool get granted => notification;
}

/// 权限状态服务：封装通知权限检测，供提醒设置页、「我的」页摘要
/// 与任务模块新增门禁复用。
///
/// 注意：所有检测均容错——插件不可用或平台不支持时按「未开启」处理，
/// 避免个别机型导致页面异常。
class PermissionStatusService {
  /// 读取通知权限状态。
  Future<ReminderPermissionStatus> reminderStatus() async {
    return ReminderPermissionStatus(notification: await notificationGranted());
  }

  /// 通知权限是否已授权（平台不支持或异常按未开启处理）。
  Future<bool> notificationGranted() async {
    try {
      return await Permission.notification.status == PermissionStatus.granted;
    } catch (_) {
      // 平台不支持时按未开启处理
      return false;
    }
  }
}

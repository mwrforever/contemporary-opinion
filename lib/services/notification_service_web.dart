import 'package:web/web.dart' as web;

import '../models/task.dart';

/// Web 端通知实现：使用 W3C `Notification` API。
///
/// 限制：浏览器没有「未来时间的系统级调度」能力，因此 [schedule] 在 Web 上
/// 为空实现；真正的「到点提醒」由 ReminderService 的 in-app Timer 触发，
/// 并在触发时调用 [showImmediate] 弹出系统通知（前提是用户已授权且处于安全上下文）。
/// 无权限 / 非安全上下文时静默降级，不抛异常、不崩溃。
class NotificationService {
  Future<void> init() async {
    // Web 端通知无需初始化；权限在 ensurePermissions / showImmediate 时按需申请。
  }

  Future<void> ensurePermissions() async {
    if (!web.window.isSecureContext) return;
    try {
      if (web.Notification.permission == 'default') {
        web.Notification.requestPermission();
      }
    } catch (_) {
      // 拒绝或异常都静默降级
    }
  }

  /// Web 无法做系统级未来调度。
  bool get supportsScheduledNotifications => false;

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required RepeatType? repeat,
    String? payload,
  }) async {
    // Web 无法做系统级未来调度，空实现（由 ReminderService 的 Timer 兜底）。
  }

  Future<void> cancel(int id) async {
    // Web 通知是一次性弹出，无可取消的已调度项。
  }

  /// 立即弹出系统通知（需已授权 + 安全上下文）。
  Future<void> showImmediate({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!web.window.isSecureContext) return;
    try {
      if (web.Notification.permission != 'granted') {
        web.Notification.requestPermission();
        if (web.Notification.permission != 'granted') return;
      }
      web.Notification(title, web.NotificationOptions(body: body));
    } catch (_) {
      // 构造失败（如非用户手势触发）静默降级
    }
  }

  void setOnTapCallback(void Function(String? payload) cb) {
    // 纯前端预览不做 Service Worker，点击回调留空。
  }
}

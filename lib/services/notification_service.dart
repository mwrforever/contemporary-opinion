/// 通知能力抽象：通过条件导出隔离平台实现。
///
/// - 移动端：`notification_service_io.dart` —— 封装 flutter_local_notifications，
///   支持系统级精准调度（App 被杀也能弹通知）。
/// - Web 端：`notification_service_web.dart` —— 使用 W3C `Notification` API，
///   仅能在「已被授权的页面 + 安全上下文」下弹出即时通知，无法做未来时间调度。
///
/// 调用方只认 [NotificationService]，无需关心平台差异。
library;

export 'notification_service_io.dart'
    if (dart.library.html) 'notification_service_web.dart';

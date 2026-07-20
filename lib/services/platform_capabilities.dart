/// 纯函数：Web 平台能力探测与降级判定。
///
/// 本文件**不依赖 `dart:html` / Flutter**，便于在 `flutter test`（宿主机原生 VM）
/// 下被直接单测。真实的浏览器探测（如 `window.isSecureContext`、
/// `window.navigator.mediaDevices`、`window.Notification`）放在平台实现文件
/// （`audio_capture_web.dart` / `notification_service_web.dart`）中，调用这里的纯函数
/// 做确定性判定，从而保证「能力 → 是否可用」「不可用 → 降级文案」的逻辑可测、可复用。
library;

/// 是否为安全上下文（https 或 localhost）。
bool isSecureContext(bool secure) => secure;

/// Web 麦克风录音是否可用：需要浏览器暴露 `mediaDevices`（getUserMedia）
/// 且当前页面处于安全上下文。
bool supportsMicCapture({
  required bool hasMediaDevices,
  required bool secureContext,
}) =>
    hasMediaDevices && secureContext;

/// Web 系统通知是否可用：需要 `Notification` API 且处于安全上下文。
bool supportsWebNotifications({
  required bool hasNotificationApi,
  required bool secureContext,
}) =>
    hasNotificationApi && secureContext;

/// 麦克风不可用时给用户的降级原因（用于 UI 提示，避免崩溃）。
String micDegradationReason({
  required bool hasMediaDevices,
  required bool secureContext,
}) {
  if (!secureContext) {
    return '当前页面不是安全上下文（需 https 或 localhost），无法使用麦克风。'
        '请用移动端获得完整体验。';
  }
  if (!hasMediaDevices) {
    return '当前浏览器不支持麦克风采集（getUserMedia）。请用移动端获得完整体验。';
  }
  return '麦克风不可用。请用移动端获得完整体验。';
}

/// 系统通知不可用时给用户的降级原因。
String notificationDegradationReason({
  required bool hasNotificationApi,
  required bool secureContext,
}) {
  if (!secureContext) {
    return '当前页面不是安全上下文（需 https 或 localhost），无法弹出系统通知。'
        '请用移动端获得完整体验。';
  }
  if (!hasNotificationApi) {
    return '当前浏览器不支持系统通知（Notification API）。请用移动端获得完整体验。';
  }
  return '系统通知不可用。请用移动端获得完整体验。';
}

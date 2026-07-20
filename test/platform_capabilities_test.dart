import 'package:daily_planner/services/platform_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Web 能力探测 (platform_capabilities)', () {
    test('非安全上下文（http 明文）→ 麦克风不可用', () {
      expect(
        supportsMicCapture(hasMediaDevices: true, secureContext: false),
        isFalse,
      );
    });

    test('无 mediaDevices API → 麦克风不可用', () {
      expect(
        supportsMicCapture(hasMediaDevices: false, secureContext: true),
        isFalse,
      );
    });

    test('安全上下文 + mediaDevices 存在 → 麦克风可用', () {
      expect(
        supportsMicCapture(hasMediaDevices: true, secureContext: true),
        isTrue,
      );
    });

    test('Web 通知：需 Notification API 且处于安全上下文', () {
      expect(
        supportsWebNotifications(hasNotificationApi: true, secureContext: true),
        isTrue,
      );
      expect(
        supportsWebNotifications(hasNotificationApi: true, secureContext: false),
        isFalse,
      );
      expect(
        supportsWebNotifications(hasNotificationApi: false, secureContext: true),
        isFalse,
      );
    });

    test('降级原因文案：麦克风（非安全上下文）提示需 https/localhost', () {
      final reason = micDegradationReason(
        hasMediaDevices: true,
        secureContext: false,
      );
      expect(reason, contains('https'));
      expect(reason, contains('localhost'));
    });

    test('降级原因文案：麦克风（无 API）', () {
      final reason = micDegradationReason(
        hasMediaDevices: false,
        secureContext: true,
      );
      expect(reason, isNotEmpty);
      expect(reason, contains('麦克风'));
    });

    test('降级原因文案：通知（无 API）', () {
      final reason = notificationDegradationReason(
        hasNotificationApi: false,
        secureContext: true,
      );
      expect(reason, isNotEmpty);
      expect(reason, contains('通知'));
    });
  });
}

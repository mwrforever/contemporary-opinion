import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:daily_planner/services/pcm_resampler.dart';
import 'package:daily_planner/services/platform_capabilities.dart';

void main() {
  group('platform_capabilities · 能力探测', () {
    test('isSecureContext 原样返回', () {
      expect(isSecureContext(true), isTrue);
      expect(isSecureContext(false), isFalse);
    });

    test('Web 麦克风可用需 mediaDevices + 安全上下文', () {
      expect(
        supportsMicCapture(hasMediaDevices: true, secureContext: true),
        isTrue,
      );
      expect(
        supportsMicCapture(hasMediaDevices: true, secureContext: false),
        isFalse,
      );
      expect(
        supportsMicCapture(hasMediaDevices: false, secureContext: true),
        isFalse,
      );
    });

    test('Web 系统通知可用需 Notification API + 安全上下文', () {
      expect(
        supportsWebNotifications(hasNotificationApi: true, secureContext: true),
        isTrue,
      );
      expect(
        supportsWebNotifications(hasNotificationApi: false, secureContext: true),
        isFalse,
      );
    });

    test('麦克风降级原因区分安全上下文与设备能力', () {
      final insecure = micDegradationReason(
        hasMediaDevices: true,
        secureContext: false,
      );
      expect(insecure, contains('安全上下文'));

      final noDevice = micDegradationReason(
        hasMediaDevices: false,
        secureContext: true,
      );
      expect(noDevice, contains('麦克风'));
    });

    test('通知降级原因区分安全上下文与 API 能力', () {
      final insecure = notificationDegradationReason(
        hasNotificationApi: true,
        secureContext: false,
      );
      expect(insecure, contains('安全上下文'));

      final noApi = notificationDegradationReason(
        hasNotificationApi: false,
        secureContext: true,
      );
      expect(noApi, contains('系统通知'));
    });
  });

  group('pcm_resampler · 音频处理', () {
    test('resampleFloat32 同速率原样返回', () {
      final input = Float32List.fromList([0.1, -0.2, 0.3]);
      final out = resampleFloat32(input, 16000, 16000);
      expect(out, equals(input));
    });

    test('resampleFloat32 空输入返回空', () {
      expect(resampleFloat32(Float32List(0), 16000, 16000), isEmpty);
    });

    test('resampleFloat32 升采样长度按比例增加', () {
      final input = Float32List.fromList([0.0, 1.0]);
      final out = resampleFloat32(input, 16000, 32000);
      expect(out.length, 4);
    });

    test('float32ToPcm16 长度为样本数*2 且范围正确', () {
      final samples = Float32List.fromList([1.0, -1.0, 0.0]);
      final pcm = float32ToPcm16(samples);
      expect(pcm.length, 6);
      // 正峰 = 32767，负峰 = -32768
      final bd = ByteData.sublistView(pcm);
      expect(bd.getInt16(0, Endian.little), 32767);
      expect(bd.getInt16(2, Endian.little), -32768);
      expect(bd.getInt16(4, Endian.little), 0);
    });

    test('float32ToPcm16 超出范围被截断', () {
      final pcm = float32ToPcm16(Float32List.fromList([2.0, -2.0]));
      final bd = ByteData.sublistView(pcm);
      expect(bd.getInt16(0, Endian.little), 32767);
      expect(bd.getInt16(2, Endian.little), -32768);
    });

    test('mixToMono 多声道取平均', () {
      final ch1 = Float32List.fromList([0.2, 0.4]);
      final ch2 = Float32List.fromList([0.4, 0.8]);
      final mono = mixToMono([ch1, ch2]);
      expect(mono[0], closeTo(0.3, 1e-6));
      expect(mono[1], closeTo(0.6, 1e-6));
    });

    test('mixToMono 单声道原样', () {
      final ch = Float32List.fromList([0.1, 0.2]);
      expect(mixToMono([ch]), equals(ch));
    });
  });
}

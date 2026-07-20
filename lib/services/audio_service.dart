import 'dart:async';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// 响铃服务：调用系统闹钟声，持续若干秒后自动停止。
class AudioService {
  final FlutterRingtonePlayer _player = FlutterRingtonePlayer();
  bool _playing = false;

  Future<void> init() async {}

  /// 持续 [duration] 秒的响铃（每 2 秒重播一次以覆盖系统提示音时长）。
  Future<void> playRing({Duration duration = const Duration(seconds: 5)}) async {
    _playing = true;
    final end = DateTime.now().add(duration);
    while (_playing && DateTime.now().isBefore(end)) {
      try {
        await _player.play(
          android: AndroidSounds.alarm,
          ios: IosSounds.alarm,
          volume: 1.0,
          asAlarm: true,
        );
      } catch (_) {
        // 部分设备不支持系统闹钟音，忽略
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    await stopRing();
  }

  Future<void> stopRing() async {
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {}
  }
}

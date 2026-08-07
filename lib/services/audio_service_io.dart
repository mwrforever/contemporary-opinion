import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

/// 响铃播放抽象：隔离 just_audio 平台通道，便于单元测试注入假实现。
abstract class RingPlayer {
  Future<void> loadAsset(String path);
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> play();
  Future<void> stop();
}

/// just_audio 实现的播放器。
class JustAudioRingPlayer implements RingPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> loadAsset(String path) => _player.setAsset(path);

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();
}

/// 移动端响铃实现：播放内置闹钟音，持续若干秒后自动停止。
///
/// 采用 just_audio（活跃维护，Java 实现兼容 AGP 9/Gradle 9）替代
/// 已停滞的 flutter_ringtone_player；通过 audio_session 配置 alarm
/// 音频会话类别，使其在静音/勿扰下仍能出声。
/// 朗读任务标题仍由 flutter_tts 负责，与本服务并行、互不影响。
class AudioService {
  AudioService({RingPlayer? player}) : _player = player ?? JustAudioRingPlayer();

  final RingPlayer _player;
  bool _assetLoaded = false;
  bool _playing = false;

  Future<void> init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.alarm,
          flags: AndroidAudioFlags.audibilityEnforced,
        ),
      ));
    } catch (_) {
      // 音频会话配置失败不阻断响铃
    }
  }

  /// 持续 [duration] 秒的响铃（每 2 秒重播一次以覆盖播放时长）。
  Future<void> playRing({Duration duration = const Duration(seconds: 5)}) async {
    _playing = true;
    try {
      if (!_assetLoaded) {
        await _player.loadAsset('assets/audio/alarm.wav');
        _assetLoaded = true;
      }
    } catch (_) {
      // 素材缺失等异常时退化为静默（与原行为一致）
    }
    final end = DateTime.now().add(duration);
    while (_playing && DateTime.now().isBefore(end)) {
      try {
        await _player.seek(Duration.zero);
        await _player.setVolume(1.0);
        await _player.play();
      } catch (_) {
        // 部分设备不支持，忽略
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

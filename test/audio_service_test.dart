// AudioService 响铃稳定性测试：注入假播放器，隔离 just_audio 平台通道
import 'package:daily_planner/services/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录型播放器替身：不触碰任何平台通道。
class FakeRingPlayer implements RingPlayer {
  int loadCount = 0;
  int playCount = 0;
  int stopCount = 0;

  @override
  Future<void> loadAsset(String path) async {
    loadCount++;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

void main() {
  group('AudioService · 响铃调用稳定性', () {
    test('stopRing() 调用不抛异常', () async {
      final audio = AudioService(player: FakeRingPlayer());
      await audio.stopRing();
    });

    test('playRing(Duration.zero) 加载素材后立即收尾，不进入播放循环', () async {
      final player = FakeRingPlayer();
      final audio = AudioService(player: player);
      await audio.playRing(duration: Duration.zero);
      expect(player.loadCount, 1);
      expect(player.playCount, 0);
      expect(player.stopCount, 1);
    });

    test('playRing() 后重复 stopRing() 仍不抛', () async {
      final player = FakeRingPlayer();
      final audio = AudioService(player: player);
      await audio.playRing(duration: Duration.zero);
      await audio.stopRing();
      expect(player.stopCount, 2);
    });
  });
}

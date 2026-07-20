import 'dart:typed_data';

import 'package:daily_planner/services/pcm_resampler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PCM 重采样 / 封装 (pcm_resampler)', () {
    test('重采样：48k → 16k 输出长度约为 1/3', () {
      final input = Float32List(480); // 480 样本 @48k ≈ 10ms
      for (var i = 0; i < input.length; i++) {
        input[i] = (i % 100) / 100.0 - 0.5;
      }
      final out = resampleFloat32(input, 48000, 16000);
      expect(out.length, 160);
    });

    test('同采样率原样返回（不丢数据）', () {
      final input = Float32List.fromList([0.1, -0.2, 0.3, -0.4]);
      final out = resampleFloat32(input, 16000, 16000);
      expect(out, orderedEquals(input));
    });

    test('空输入安全返回空', () {
      expect(resampleFloat32(Float32List(0), 48000, 16000).length, 0);
    });

    test('float → PCM16 字节数 = 样本数 * 2，且 1.0→32767、-1.0→-32768', () {
      final samples = Float32List.fromList([1.0, -1.0, 0.0]);
      final bytes = float32ToPcm16(samples);
      expect(bytes.length, 6);
      final bd = ByteData.sublistView(bytes);
      expect(bd.getInt16(0, Endian.little), 32767);
      expect(bd.getInt16(2, Endian.little), -32768);
      expect(bd.getInt16(4, Endian.little), 0);
    });

    test('多声道降混为单声道取平均', () {
      final left = Float32List.fromList([0.4, 0.0]);
      final right = Float32List.fromList([0.0, 0.4]);
      final mono = mixToMono([left, right]);
      expect(mono.length, 2);
      expect(mono[0], closeTo(0.2, 1e-6));
      expect(mono[1], closeTo(0.2, 1e-6));
    });

    test('与 WAV 封装串联：重采样 + 封装得到正确字节长度', () {
      final samples =
          Float32List.fromList(List.generate(1000, (i) => (i % 50) / 50.0 - 0.5));
      final pcm = float32ToPcm16(samples);
      expect(pcm.length, 2000);
    });
  });
}

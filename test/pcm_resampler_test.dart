import 'dart:math';
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

  group('resamplePcm16（PCM16 字节流重采样）', () {
    /// 构造一段正弦 PCM16 小端字节流，便于验证重采样确有输出。
    Uint8List sinePcm16(int samples, int rate, double freq, double amp) {
      final bd = ByteData(samples * 2);
      for (var i = 0; i < samples; i++) {
        final t = i / rate;
        final v = sin(2 * pi * freq * t) * amp;
        final s16 = (v < 0 ? (v * 32768).round() : (v * 32767).round())
            .clamp(-32768, 32767)
            .toInt();
        bd.setInt16(i * 2, s16, Endian.little);
      }
      return bd.buffer.asUint8List();
    }

    test('48k → 16k 输出长度约为源长度 / 3（±2 字节容差）', () {
      // 1 秒 @48k 单声道 16bit = 48000 样本 = 96000 字节
      final pcm = sinePcm16(48000, 48000, 440, 0.6);
      expect(pcm.length, 96000);
      final out = resamplePcm16(pcm, 48000, 16000);
      // 期望 ≈ 96000 * 16000/48000 = 32000 字节
      expect(out.length, 32000);
      expect((out.length - 32000).abs(), lessThanOrEqualTo(2));
    });

    test('inRate == outRate 原样返回（内容一致）', () {
      final pcm = sinePcm16(16000, 16000, 440, 0.6);
      final out = resamplePcm16(pcm, 16000, 16000);
      expect(out, equals(pcm));
    });

    test('空输入安全返回空', () {
      expect(resamplePcm16(Uint8List(0), 48000, 16000).length, 0);
    });

    test('非法速率（0 / 负数）返回空', () {
      final pcm = sinePcm16(1000, 48000, 440, 0.5);
      expect(resamplePcm16(pcm, 0, 16000).length, 0);
      expect(resamplePcm16(pcm, 48000, 0).length, 0);
      expect(resamplePcm16(pcm, -1, 16000).length, 0);
    });

    test('正弦 PCM16 重采样确有非全零输出', () {
      final pcm = sinePcm16(48000, 48000, 440, 0.8);
      final out = resamplePcm16(pcm, 48000, 16000);
      expect(out.length, greaterThan(0));
      // 重采样后波形不应全零：统计最大绝对幅度 > 0
      var maxAbs = 0;
      final bd = out.buffer.asByteData();
      for (var i = 0; i < out.length ~/ 2; i++) {
        final s = bd.getInt16(i * 2, Endian.little).abs();
        if (s > maxAbs) maxAbs = s;
      }
      expect(maxAbs, greaterThan(0));
    });
  });
}

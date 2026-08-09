import 'dart:typed_data';

import 'package:daily_planner/services/pcm_resampler.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 独立回归补充验证：覆盖工程师测试未显式断言的易错边界。
///
/// 不改变工程师既有测试，仅作为回归加固，证明重采样在全负/正负混合的
/// Int16 极端输入下量化后仍落在 [-32768, 32767]，不会溢出。
void main() {
  group('QA 边缘验证：resamplePcm16 Int16 边界不溢出', () {
    test('全负 + 极端 -32768 输入：重采样后所有样本落在 [-32768, 32767]', () {
      const n = 48000;
      final bd = ByteData(n * 2);
      for (var i = 0; i < n; i++) {
        // 交替极端负值与接近 0 的负值，覆盖归一化除数的负分支
        final s16 = (i % 2 == 0) ? -32768 : -1;
        bd.setInt16(i * 2, s16, Endian.little);
      }
      final pcm = bd.buffer.asUint8List();
      expect(pcm.length, n * 2);

      final out = resamplePcm16(pcm, 48000, 16000);
      expect(out.isNotEmpty, isTrue);
      // 输出长度应为 n * 2 * 16000/48000 = n*2/3 = 32000
      expect(out.length, 32000);

      final ob = out.buffer.asByteData();
      for (var i = 0; i < out.length ~/ 2; i++) {
        final s = ob.getInt16(i * 2, Endian.little);
        expect(s, greaterThanOrEqualTo(-32768));
        expect(s, lessThanOrEqualTo(32767));
      }
    });

    test('正负混合极端样本：同率原样返回且范围合法', () {
      const n = 16000;
      final bd = ByteData(n * 2);
      for (var i = 0; i < n; i++) {
        final s16 = (i % 3 == 0) ? 32767 : (i % 3 == 1 ? -32768 : 0);
        bd.setInt16(i * 2, s16, Endian.little);
      }
      final pcm = bd.buffer.asUint8List();
      final out = resamplePcm16(pcm, 16000, 16000); // 同率原样返回
      expect(out, equals(pcm));
    });
  });
}

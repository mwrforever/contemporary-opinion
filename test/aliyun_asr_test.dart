import 'dart:typed_data';

import 'package:daily_planner/services/aliyun_asr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AliyunAsrService.buildWav', () {
    Uint8List readBytes(Uint8List b, int off, int len) =>
        b.sublist(off, off + len);

    String ascii(Uint8List b) => String.fromCharCodes(b);

    int u32(Uint8List b, int off) =>
        b.buffer.asByteData().getUint32(off, Endian.little);

    test('封装标准 WAV 头，长度=44+数据', () {
      final pcm = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final wav = AliyunAsrService.buildWav(pcm,
          sampleRate: 16000, numChannels: 1, bitsPerSample: 16);

      expect(wav.length, 44 + pcm.length);
      expect(ascii(readBytes(wav, 0, 4)), 'RIFF');
      expect(ascii(readBytes(wav, 8, 4)), 'WAVE');
      expect(ascii(readBytes(wav, 12, 4)), 'fmt ');
      expect(ascii(readBytes(wav, 36, 4)), 'data');
    });

    test('fmt 设为 PCM(1)、采样率/通道/位深正确', () {
      final pcm = Uint8List(200);
      final wav = AliyunAsrService.buildWav(pcm,
          sampleRate: 16000, numChannels: 1, bitsPerSample: 16);

      // fmt chunk: audioFormat=1(PCM) @16, numChannels @18, sampleRate @24
      expect(u32(wav, 16), 16); // fmt chunk 大小
      expect(wav.buffer.asByteData().getUint16(20, Endian.little), 1); // PCM
      expect(wav.buffer.asByteData().getUint16(22, Endian.little), 1); // 单声道
      expect(u32(wav, 24), 16000); // 采样率
    });

    test('data chunk 大小与原始 PCM 一致且尾部数据完整', () {
      final pcm = Uint8List.fromList(List.filled(500, 0xAB));
      final wav = AliyunAsrService.buildWav(pcm,
          sampleRate: 16000, numChannels: 1, bitsPerSample: 16);

      expect(u32(wav, 40), pcm.length); // data size 字段
      expect(readBytes(wav, 44, pcm.length), equals(pcm)); // 尾部即原 PCM
    });

    test('多声道参数正确写入 blockAlign/byteRate', () {
      // 2 通道 16bit 16k → blockAlign=4, byteRate=64000
      final pcm = Uint8List(400);
      final wav = AliyunAsrService.buildWav(pcm,
          sampleRate: 16000, numChannels: 2, bitsPerSample: 16);

      expect(wav.buffer.asByteData().getUint16(32, Endian.little), 4); // blockAlign
      expect(u32(wav, 28), 64000); // byteRate
      expect(wav.buffer.asByteData().getUint16(22, Endian.little), 2); // channels
    });
  });
}

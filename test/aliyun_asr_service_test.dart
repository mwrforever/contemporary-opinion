import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:daily_planner/services/aliyun_asr_service.dart';
import 'package:daily_planner/services/audio_capture.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// 测试替身：录音返回可控的 PCM 分片，并暴露可定制的真实采样率。
///
/// 复现 Web 端 record_web 把请求率改写为设备真实率（如 48000）的场景：
/// 通过重写 [realSampleRate] 让上层按「真实率」而非硬编码 16k 决策。
class FakeCapture extends AudioCapture {
  final int _rate;
  final List<Uint8List> chunks;

  FakeCapture(this._rate, this.chunks);

  @override
  int get realSampleRate => _rate;

  @override
  bool get isRecording => false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream() async {
    final ctrl = StreamController<Uint8List>();
    for (final c in chunks) {
      ctrl.add(c);
    }
    // 保持打开，模拟「仍在录音」，由服务侧 stop() 结束。
    return ctrl.stream;
  }

  @override
  Future<Uint8List> stop() async => Uint8List(0);

  @override
  Future<void> dispose() async {}
}

/// 测试替身：拦截 /chat/completions 请求，记录请求体并返回固定 JSON。
class FakeHttpClient extends http.BaseClient {
  String? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastBody = await request.finalize().bytesToString();
    final body = jsonEncode({
      'choices': [
        {'message': {'content': '今天下午三点开会'}}
      ]
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  @override
  void close() {}
}

const String _endpoint = 'https://example.com/chat/completions';

/// 构造一段正弦 PCM16 小端字节流（单声道 16bit）。
Uint8List _sinePcm16(int samples, int rate, double freq, double amp) {
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

/// 从请求体 JSON 中解析出 WAV 字节（data:audio/wav;base64,...）。
Uint8List _wavFromBody(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final msg = (decoded['messages'] as List).first as Map<String, dynamic>;
  final content = (msg['content'] as List).first as Map<String, dynamic>;
  final audio = content['input_audio'] as Map<String, dynamic>;
  final dataUrl = audio['data'] as String;
  expect(dataUrl, startsWith('data:audio/wav;base64,'));
  return base64Decode(dataUrl.split(',').last);
}

void main() {
  // record 包构造 AudioRecorder 会走 MethodChannel，测试环境无原生实现，
  // 这里桩掉该通道，仅让构造成功；FakeCapture 已重写 startStream/stop 等，
  // 不会真正调用录音硬件。
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (MethodCall call) async => null,
  );

  group('AliyunAsrService · 采样率重采样（修复 Bug）', () {
    test('真实率 48000：送入 buildWav 的 PCM 已被重采样为 16k 等价长度，'
        '且 WAV 头声明 16000', () async {
      // 1 秒 @48k 单声道 16bit = 48000 样本 = 96000 字节
      final pcm48k = _sinePcm16(48000, 48000, 440, 0.6);
      expect(pcm48k.length, 96000);

      final client = FakeHttpClient();
      final capture = FakeCapture(48000, [pcm48k]);
      final svc = AliyunAsrService(
        apiKey: 'test-key',
        endpoint: _endpoint,
        client: client,
        capture: capture,
      );

      final future = svc.transcribe(onPartial: (_) {});
      await Future.delayed(const Duration(milliseconds: 30));
      svc.stop();
      final text = await future;
      expect(text, isNotEmpty);

      final wav = _wavFromBody(client.lastBody!);
      // WAV fmt 头采样率字段（offset 24）应为 16000
      expect(wav.buffer.asByteData().getUint32(24, Endian.little), 16000);

      // data 段长度应为 96000 * 16000/48000 = 32000（±2 字节容差）
      final dataLen = wav.length - 44;
      expect(dataLen, 32000);
      expect((dataLen - 32000).abs(), lessThanOrEqualTo(2));
      // 关键：确实被重采样（不再是原始 96000），否则仍会 3× 错配
      expect(dataLen, isNot(equals(96000)));
    });

    test('真实率 16000：无需重采样，WAV 数据长度与原 PCM 一致', () async {
      // 1 秒 @16k 单声道 16bit = 16000 样本 = 32000 字节
      final pcm16k = _sinePcm16(16000, 16000, 440, 0.6);
      expect(pcm16k.length, 32000);

      final client = FakeHttpClient();
      final capture = FakeCapture(16000, [pcm16k]);
      final svc = AliyunAsrService(
        apiKey: 'test-key',
        endpoint: _endpoint,
        client: client,
        capture: capture,
      );

      final future = svc.transcribe(onPartial: (_) {});
      await Future.delayed(const Duration(milliseconds: 30));
      svc.stop();
      await future;

      final wav = _wavFromBody(client.lastBody!);
      expect(wav.buffer.asByteData().getUint32(24, Endian.little), 16000);
      // 16k 路径不重采样，data 段长度应等于原 PCM 长度
      expect(wav.length - 44, 32000);
    });
  });
}

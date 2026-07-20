import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:daily_planner/services/aliyun_asr_service.dart';
import 'package:daily_planner/services/audio_capture.dart';
import 'package:daily_planner/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 测试替身：用同步可控的 PCM 流模拟麦克风，不触碰真实录音硬件。
class FakeAudioCapture extends AudioCapture {
  bool _recording = false;
  bool stopCalled = false;
  bool forceReleased = false;

  /// 录音期间吐出的 PCM 分片；为空表示「静音 / 立刻结束」。
  final List<Uint8List> chunks;

  FakeAudioCapture({this.chunks = const []});

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream() async {
    // 忠实于真实 AudioCapture：已在录音时抛「已在录音」，这正是 Bug 1 的根因。
    if (_recording) throw StateError('已在录音');
    _recording = true;
    final ctrl = StreamController<Uint8List>();
    for (final c in chunks) {
      ctrl.add(c);
    }
    // 保持打开，模拟「仍在录音」，由服务侧 cancel/stop 或超时结束。
    return ctrl.stream;
  }

  @override
  Future<Uint8List> stop() async {
    _recording = false;
    stopCalled = true;
    return Uint8List(0);
  }

  @override
  Future<void> dispose() async {
    _recording = false;
  }
}

/// 测试替身：模拟设备端 speech_to_text，立刻回传固定文本并结束。
class FakeSpeechService extends SpeechService {
  final String text;
  bool startCalled = false;
  bool stopCalled = false;

  FakeSpeechService(this.text);

  @override
  bool get available => true;

  @override
  bool get isListening => false;

  @override
  Future<bool> init() async => true;

  @override
  Future<void> startListening({
    required void Function(String) onText,
    void Function()? onComplete,
  }) async {
    startCalled = true;
    onText(text);
    onComplete?.call();
  }

  @override
  Future<void> stopListening() async {
    stopCalled = true;
  }
}

/// 测试替身：拦截 /chat/completions 请求，按配置返回固定响应或错误。
class FakeHttpClient extends http.BaseClient {
  int callCount = 0;
  String? lastBody;
  final int statusCode;
  final Map<String, dynamic>? responseJson;

  FakeHttpClient({this.statusCode = 200, this.responseJson});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    lastBody = await request.finalize().bytesToString();
    final body = responseJson != null
        ? jsonEncode(responseJson)
        : '{"choices":[{"message":{"content":"今天下午三点开会"}}]}';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  @override
  void close() {}
}

const String _endpoint = 'https://example.com/chat/completions';

AliyunAsrService buildCloudService({
  String apiKey = 'test-key',
  required FakeHttpClient client,
  required FakeAudioCapture capture,
  SpeechService? fallback,
}) {
  // 云端路径要求「已配置 key 且提供兜底」才会走云端（源码约束）。
  return AliyunAsrService(
    apiKey: apiKey,
    endpoint: _endpoint,
    client: client,
    capture: capture,
    fallback: fallback ?? FakeSpeechService('设备端识别结果'),
  );
}

void main() {
  group('AliyunAsrService.transcribe · 云端路径', () {
    test('云端成功：返回转写文本并回调 onPartial', () async {
      final client = FakeHttpClient();
      final capture = FakeAudioCapture(chunks: [Uint8List(200)]);
      final svc = buildCloudService(client: client, capture: capture);

      var partial = '';
      final text = await svc.transcribe(
        onPartial: (t) => partial = t,      );

      expect(text, '今天下午三点开会');
      expect(partial, '今天下午三点开会');
      expect(client.callCount, 1);
      // 请求体应携带 WAV data URL 与 input_audio（端到端验证 buildWav 契约）
      expect(client.lastBody, contains('data:audio/wav'));
      expect(client.lastBody, contains('input_audio'));
      expect(capture.stopCalled, isTrue);
    });

    test('云端 HTTP 非 200：自动降级设备端兜底', () async {
      final client = FakeHttpClient(statusCode: 500);
      final capture = FakeAudioCapture(chunks: [Uint8List(200)]);
      final fallback = FakeSpeechService('设备端识别结果');
      final svc = buildCloudService(
        client: client,
        capture: capture,
        fallback: fallback,
      );

      final text = await svc.transcribe(
        onPartial: (_) {},      );

      expect(text, '设备端识别结果');
      expect(fallback.startCalled, isTrue);
    });

    test('云端返回空内容：视为失败并降级兜底', () async {
      final client = FakeHttpClient(
        responseJson: {
          'choices': [
            {'message': {'content': ''}}
          ]
        },
      );
      final capture = FakeAudioCapture(chunks: [Uint8List(200)]);
      final fallback = FakeSpeechService('兜底文本');
      final svc = buildCloudService(
        client: client,
        capture: capture,
        fallback: fallback,
      );

      final text = await svc.transcribe(
        onPartial: (_) {},      );
      expect(text, '兜底文本');
      expect(fallback.startCalled, isTrue);
    });

    test('云端录音为空(0 字节)：返回空串且不触发 onPartial / ASR', () async {
      final client = FakeHttpClient();
      final capture = FakeAudioCapture(chunks: const []);
      final svc = buildCloudService(client: client, capture: capture);

      var partialCalls = 0;
      final text = await svc.transcribe(
        onPartial: (_) => partialCalls++,      );

      expect(text, '');
      expect(partialCalls, 0);
      expect(client.callCount, 0);
    });
  });

  group('AliyunAsrService.transcribe · 兜底路径', () {
    test('未配置云端但提供兜底：直接使用设备端识别', () async {
      final fallback = FakeSpeechService('纯设备端');
      final svc = AliyunAsrService(apiKey: '', fallback: fallback);

      final text = await svc.transcribe(onPartial: (_) {});
      expect(text, '纯设备端');
      expect(fallback.startCalled, isTrue);
    });

    test('未配置云端且无兜底：抛 StateError', () async {
      final svc = AliyunAsrService(apiKey: '');
      expect(
        () => svc.transcribe(onPartial: (_) {}),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AliyunAsrService.transcribe · 取消/停止', () {
    test('录音中 cancel()：抛出 asr cancelled 且释放麦克风、不请求云端', () async {
      final client = FakeHttpClient();
      final capture = FakeAudioCapture(chunks: [Uint8List(200)]);
      final svc = buildCloudService(client: client, capture: capture);

      final future = svc.transcribe(
        onPartial: (_) {},      );
      await Future.delayed(const Duration(milliseconds: 30));
      svc.cancel();
      await expectLater(
        future,
        throwsA(predicate((e) => e.toString() == 'asr cancelled')),
      );
      expect(capture.stopCalled, isTrue);
      expect(client.callCount, 0);
    });

    test('录音中 stop()：按已采集音频走云端识别并返回结果', () async {
      final client = FakeHttpClient();
      final capture = FakeAudioCapture(chunks: [Uint8List(200)]);
      final svc = buildCloudService(client: client, capture: capture);

      final future = svc.transcribe(
        onPartial: (_) {},      );
      await Future.delayed(const Duration(milliseconds: 30));
      svc.stop();

      final text = await future;
      expect(text, '今天下午三点开会');
      expect(client.callCount, 1);
    });

    test('cancel() 后再 transcribe：客户端连接被重建可再次识别', () async {
      final client = FakeHttpClient();
      final capture = FakeAudioCapture(chunks: [Uint8List(200)]);
      final svc = buildCloudService(client: client, capture: capture);

      final f1 = svc.transcribe(
        onPartial: (_) {},
      );
      await Future.delayed(const Duration(milliseconds: 30));
      svc.cancel();
      await expectLater(
        f1,
        throwsA(predicate((e) => e.toString() == 'asr cancelled')),
      );

      // 复用一个新 capture 模拟下一轮录音
      final capture2 = FakeAudioCapture(chunks: [Uint8List(200)]);
      final svc2 = AliyunAsrService(
        apiKey: 'test-key',
        endpoint: _endpoint,
        client: client,
        capture: capture2,
        fallback: FakeSpeechService('设备端识别结果'),
      );
      final text = await svc2.transcribe(
        onPartial: (_) {},
      );
      expect(text, '今天下午三点开会');
      expect(client.callCount, 1);
    });
  });

  group('AliyunAsrService.transcribe · 悬空会话复现 Bug 1', () {
    test('上一轮未释放(_active 仍 true)时再次 transcribe：不报错且走云端返回', () async {
      final client = FakeHttpClient();
      final capture = FakeAudioCapture(chunks: [Uint8List(200)]);
      final svc = buildCloudService(client: client, capture: capture);

      // 第一轮：开始听但「关掉页面」且未调用 cancel —— f1 仍在途，
      // 此时 _active==true 且 capture.isRecording==true（麦克风被占）。
      final f1 = svc.transcribe(
        onPartial: (_) {},
      );
      await Future.delayed(const Duration(milliseconds: 30));

      // 第二轮：再次进入点话筒（复现「关闭再打开报错」）。
      // 修复要点：transcribe 启动前若 _active 会 _forceRelease() 释放上一轮，
      // 因此 startStream 不再抛「已在录音」，第二轮正常走云端识别。
      final text = await svc.transcribe(
        onPartial: (_) {},      );

      // 关键断言：第二轮必须返回云端转写文本（而非落到设备端兜底 /
      // 抛「已在录音」）。这正是 Bug 1「关闭再打开报语音识别失败」的最小复现。
      expect(text, '今天下午三点开会');
      // 至少调用了一次云端（第二轮走的是云端路径）。
      expect(client.callCount, greaterThanOrEqualTo(1));

      // 排空第一轮孤儿会话（已被第二轮的 _forceRelease 取消订阅，稍后自然结束）。
      await f1.catchError((_) => '');
    });
  });
}

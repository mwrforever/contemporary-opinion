import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/aliyun_config.dart';
import 'audio_capture.dart';
import 'speech_service.dart';

/// 语音识别被主动取消（页面关闭 / 中止），不应触发兜底或错误提示。
class _AsrCancelled implements Exception {
  const _AsrCancelled();
  @override
  String toString() => 'asr cancelled';
}

/// 阿里云语音识别服务：Qwen3-ASR-Flash（百炼 / DashScope）。
///
/// 接入：OpenAI 兼容 `/chat/completions`，音频以 `input_audio` 的 base64 Data URL
/// （WAV）传入；属于「录完一段再识别」的文件识别，而非实时流式。
/// 鉴权：仅需 [apiKey]（DashScope API Key），与排期服务 [AliyunScheduleService] 共用。
///
/// **兜底**：未配置 key / 连接失败 / 解析异常时，自动退回设备端
/// [SpeechService]（speech_to_text），保证 Demo 在无云端配置时仍可录音。
class AliyunAsrService {
  final String apiKey;
  final String model;
  final String endpoint;
  final SpeechService? fallback;

  http.Client _client;
  final AudioCapture _capture;

  bool _active = false;
  bool _stopRequested = false;
  bool _aborted = false;
  bool _closed = false;
  Completer<void>? _stopCompleter;
  StreamSubscription<Uint8List>? _sub;

  AliyunAsrService({
    required this.apiKey,
    this.model = AliyunConfig.asrModel,
    this.endpoint = AliyunConfig.chatCompletionsUrl,
    this.fallback,
    http.Client? client,
    AudioCapture? capture,
  })  : _client = client ?? http.Client(),
        _capture = capture ?? AudioCapture();

  bool get _configured => apiKey.isNotEmpty;

  /// 录音并识别，返回最终转写文本。
  ///
  /// [onPartial] 在识别完成后回传最终结果。录音**不会自动超时停止**，
  /// 只能由用户点击停止（[stop]）或取消（[cancel]）才结束；若未配置云端，
  /// 则委托 [fallback]（设备端识别）。
  Future<String> transcribe({
    required void Function(String) onPartial,
  }) async {
    if (_active) {
      await _forceRelease();
      _active = false;
    }
    if (_closed) {
      _client = http.Client();
      _closed = false;
    }
    _active = true;
    _stopRequested = false;
    _aborted = false;
    _stopCompleter = Completer<void>();
    try {
      if (!_configured || fallback == null) {
        return await _transcribeFallback(onPartial);
      }
      try {
        return await _transcribeCloud(onPartial);
      } on _AsrCancelled {
        rethrow;
      } catch (_) {
        if (_stopRequested || _aborted) rethrow;
        return await _transcribeFallback(onPartial);
      }
    } finally {
      _active = false;
      _stopCompleter = null;
    }
  }

  /// 结束本次识别：继续处理已采集的音频，由用户点击停止触发（不再有自动超时）。
  void stop() {
    _stopRequested = true;
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete();
    }
  }

  /// 取消本次识别：页面销毁时彻底中止、释放麦克风并关闭连接，
  /// 不触发兜底或错误提示（由 [_AsrCancelled] 透传）。
  void cancel() {
    _aborted = true;
    _stopRequested = true;
    try {
      _client.close();
    } catch (_) {}
    _closed = true;
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete();
    }
    _forceRelease();
  }

  Future<void> _forceRelease() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _capture.stop();
    } catch (_) {}
  }

  Future<String> _transcribeFallback(void Function(String) onPartial) async {
    final sp = fallback;
    if (sp == null) throw StateError('未配置云端 ASR，且无本地兜底');
    if (!sp.available) {
      final ok = await sp.init();
      if (!ok) throw StateError('本地语音识别不可用');
    }
    final completer = Completer<String>();
    var last = '';
    await sp.startListening(
      onText: (text) {
        last = text;
        onPartial(text);
      },
      onComplete: () {
        if (!completer.isCompleted) completer.complete(last);
      },
    );
    await Future.any([completer.future, _stopCompleter!.future]);
    if (_aborted) {
      await sp.stopListening();
      throw const _AsrCancelled();
    }
    if (_stopRequested) {
      await sp.stopListening();
      if (!completer.isCompleted) completer.complete(last);
    }
    return completer.future;
  }

  Future<String> _transcribeCloud(
    void Function(String) onPartial,
  ) async {
    if (_capture.isRecording) {
      try {
        await _capture.stop();
      } catch (_) {}
    }
    final chunks = <Uint8List>[];
    final stream = await _capture.startStream();
    _sub = stream.listen(chunks.add);
    await _stopCompleter!.future;
    await _sub?.cancel();
    _sub = null;

    if (_aborted) {
      await _capture.stop();
      throw const _AsrCancelled();
    }
    await _capture.stop();

    final length = chunks.fold<int>(0, (sum, c) => sum + c.lengthInBytes);
    if (length == 0) {
      return '';
    }

    final pcm = Uint8List(length);
    var offset = 0;
    for (final c in chunks) {
      pcm.setRange(offset, offset + c.lengthInBytes, c);
      offset += c.lengthInBytes;
    }

    // 2) 封装为 WAV（Qwen3-ASR 接受 data:audio/wav;base64,...）
    final wav = buildWav(pcm,
        sampleRate: 16000, numChannels: 1, bitsPerSample: 16);
    final dataUrl = 'data:audio/wav;base64,${base64Encode(wav)}';

    // 3) 调用 Qwen3-ASR-Flash
    final body = jsonEncode({
      'model': model,
      'stream': false,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_audio',
              'input_audio': {'data': dataUrl}
            }
          ]
        }
      ],
      'asr_options': {'enable_itn': false, 'language': 'zh'}
    });

    final resp = await _client.post(
      Uri.parse(endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (resp.statusCode != 200) {
      throw Exception('DashScope ASR ${resp.statusCode}: ${resp.body}');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = decoded['choices']?[0]?['message']?['content'] as String?;
    final text = (content ?? '').trim();
    if (text.isEmpty) throw Exception('ASR 返回为空');
    onPartial(text);
    return text;
  }

  /// 将裸 PCM 字节封装为标准 WAV 文件头（纯函数，便于单测）。
  static Uint8List buildWav(
    Uint8List pcm, {
    required int sampleRate,
    required int numChannels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    final dataSize = pcm.lengthInBytes;
    final out = BytesBuilder();
    out.add(utf8.encode('RIFF'));
    out.add(_u32(36 + dataSize));
    out.add(utf8.encode('WAVE'));
    out.add(utf8.encode('fmt '));
    out.add(_u32(16));
    out.add(_u16(1)); // PCM
    out.add(_u16(numChannels));
    out.add(_u32(sampleRate));
    out.add(_u32(byteRate));
    out.add(_u16(blockAlign));
    out.add(_u16(bitsPerSample));
    out.add(utf8.encode('data'));
    out.add(_u32(dataSize));
    out.add(pcm);
    return out.toBytes();
  }

  static Uint8List _u32(int v) {
    final b = Uint8List(4);
    b.buffer.asByteData().setUint32(0, v, Endian.little);
    return b;
  }

  static Uint8List _u16(int v) {
    final b = Uint8List(2);
    b.buffer.asByteData().setUint16(0, v, Endian.little);
    return b;
  }
}

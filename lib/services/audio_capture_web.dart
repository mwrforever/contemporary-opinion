import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:web/web.dart' as web;

import 'platform_capabilities.dart';

/// Web 端录音采集。
///
/// 实际 PCM 采集**委托给 `record` 包**（record_web 1.3.0 已支持
/// PCM16 流式采集，且已接入本项目），对上层暴露与移动端一致的
/// [startStream]/[stop] 契约；这里额外做 Web 专属的
/// 「能力探测 + 优雅降级」：非安全上下文（非 https/localhost）时直接抛出
/// 友好的降级说明，而不是让浏览器原生异常冒泡导致崩溃。
///
/// 关于「自己用 dart:html 重写 MediaRecorder」：本 SDK 中 `dart:html`
/// 已库级 `@Deprecated`，且从零手写 Web Audio 采集无法在当前环境用浏览器
/// 验证，故选择复用已验证的 record_web 实现，更稳妥、更易维护。
class AudioCapture {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;

  Future<bool> hasPermission() async {
    if (!web.window.isSecureContext) return false;
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  /// 是否正在录音（供 ASR 服务防御性释放残留会话）。
  bool get isRecording => _recording;

  Future<Stream<Uint8List>> startStream() async {
    if (_recording) throw StateError('已在录音');
    if (!web.window.isSecureContext) {
      throw StateError(micDegradationReason(
        hasMediaDevices: true,
        secureContext: false,
      ));
    }
    _recording = true;
    return _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 256000,
    ));
  }

  Future<Uint8List> stop() async {
    if (!_recording) return Uint8List(0);
    _recording = false;
    await _recorder.stop();
    return Uint8List(0);
  }

  Future<void> dispose() async {
    _recording = false;
    await _recorder.dispose();
  }
}

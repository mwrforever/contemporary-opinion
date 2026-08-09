import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// 移动端录音采集：封装 `record` 包，输出 PCM16@16k 单声道字节流，
/// 与 [AliyunAsrService.buildWav] 的输入契约完全一致，移动端行为保持不变。
class AudioCapture {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;

  /// 申请/查询麦克风权限。
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// 是否正在录音（供 ASR 服务防御性释放残留会话）。
  bool get isRecording => _recording;

  /// 移动端 record 遵守请求率，恒为 16000。
  int get realSampleRate => 16000;

  /// 开始流式录音，返回 PCM16@16k 单声道字节流。
  Future<Stream<Uint8List>> startStream() async {
    if (_recording) throw StateError('已在录音');
    _recording = true;
    return _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 256000,
    ));
  }

  /// 停止录音（移动端字节已随流发出，这里返回空）。
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

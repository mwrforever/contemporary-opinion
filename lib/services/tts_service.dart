import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// 语音播报服务：将提醒内容以中文朗读出来。
class TtsService {
  final FlutterTts _tts = FlutterTts();

  Future<void> init() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.95);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  /// 朗读并**等待本次播报完成**后返回（用于「每条语音播完再间隔 2 秒」的循环提醒）。
  /// 通过 FlutterTts 的 completion handler 感知播报结束；设置 [maxWait] 兜底，
  /// 防止个别平台 completion 不回调导致无限等待。
  Future<void> speakAndAwait(String text, {Duration maxWait = const Duration(seconds: 8)}) async {
    if (text.isEmpty) return;
    await _tts.stop();
    final completer = Completer<void>();
    _pending = completer;
    _tts.setCompletionHandler(() {
      if (_pending != null && !_pending!.isCompleted) _pending!.complete();
    });
    await _tts.speak(text);
    try {
      await completer.future.timeout(maxWait, onTimeout: () {});
    } finally {
      if (_pending == completer) _pending = null;
      // 清除 handler，避免残留回调影响后续播报
      try {
        _tts.setCompletionHandler(() {});
      } catch (_) {}
    }
  }

  /// 当前正在等待完成的播报（串行保证：循环播报为顺序调用，无竞态）。
  Completer<void>? _pending;

  /// 立即中断当前等待中的播报（让 [speakAndAwait] 尽快返回），并停止 TTS 引擎。
  Future<void> interrupt() async {
    if (_pending != null && !_pending!.isCompleted) _pending!.complete();
    _pending = null;
    await _tts.stop();
  }

  Future<void> stop() async {
    _pending = null;
    await _tts.stop();
  }
}

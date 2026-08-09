import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// 播报音色描述：名称 + 区域 + 引擎标识。
///
/// [id] 为引擎提供的稳定标识（iOS 为 identifier）；缺失时以
/// 名称+区域拼接作为唯一键，保证各平台都能选中同一语音。
class TtsVoice {
  const TtsVoice({required this.name, required this.locale, this.id});

  /// 音色展示名称（如「普通话 · 女声」）
  final String name;

  /// 语音区域（如 zh-CN）
  final String locale;

  /// 引擎稳定标识（iOS identifier；Android 通常为空）
  final String? id;

  /// 唯一键：优先引擎标识，否则名称+区域。
  String get key => id ?? '$name|$locale';

  /// 转为 flutter_tts setVoice 需要的参数（name/locale 为通用字段）。
  Map<String, String> toVoiceMap() => {
        'name': name,
        'locale': locale,
        'identifier': ?id,
      };
}

/// 语音播报服务：将提醒内容以中文朗读出来。
///
/// 支持音色切换：音色列表来自系统 TTS 引擎（getVoices），随机型不同；
/// 选中音色仅在播报前按需应用，引擎不可用时静默回退默认音色。
class TtsService {
  final FlutterTts _tts = FlutterTts();

  /// 当前选中音色键（null = 系统默认音色）。
  String? _voiceId;

  /// 已应用音色键：避免每次播报重复查询引擎。
  String? _appliedVoiceId;

  Future<void> init() async {
    await _tts.setLanguage('zh-CN');
    // 语速 0.5 = Android/iOS 正常语速（flutter_tts 映射：Android 1.0 ≈ flutter 0.5）
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await _applyVoice();
    await _tts.stop();
    await _tts.speak(text);
  }

  /// 设置播报音量（0.0-1.0），用于用户提醒音量设置。
  Future<void> setVolume(double volume) async {
    await _tts.setVolume(volume.clamp(0.0, 1.0));
  }

  /// 朗读并**等待本次播报完成**后返回（用于「每条语音播完再间隔 2 秒」的循环提醒）。
  /// 通过 FlutterTts 的 completion handler 感知播报结束；设置 [maxWait] 兜底，
  /// 防止个别平台 completion 不回调导致无限等待。
  Future<void> speakAndAwait(String text, {Duration maxWait = const Duration(seconds: 8)}) async {
    if (text.isEmpty) return;
    await _applyVoice();
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

  /// 读取系统语音引擎的中文音色列表；引擎不可用或异常时返回空列表。
  ///
  /// 返回内容来自平台 getVoices，iOS 含 identifier/gender，
  /// Android 部分引擎返回名称+区域；仅保留 zh 前缀语音。
  Future<List<TtsVoice>> availableVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final voices = <TtsVoice>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString();
        final locale = (item['locale'] ?? '').toString();
        // 跳过无名称/无区域或非中文语音，避免列表混入无关语言
        if (name.isEmpty || locale.isEmpty) continue;
        if (!locale.toLowerCase().startsWith('zh')) continue;
        voices.add(
          TtsVoice(name: name, locale: locale, id: item['identifier']?.toString()),
        );
      }
      return voices;
    } catch (_) {
      // 引擎不支持查询时按无可选音色处理
      return const [];
    }
  }

  /// 当前选中音色键（null = 系统默认）。
  String? get currentVoiceId => _voiceId;

  /// 切换播报音色：[voiceId] 为 [TtsVoice.key]（null 恢复系统默认）。
  ///
  /// 引擎中找不到对应音色时保持默认，不抛出异常。
  Future<void> setVoice(String? voiceId) async {
    _voiceId = voiceId;
    _appliedVoiceId = null;
    await _applyVoice();
  }

  /// 在播报前按需应用音色：仅在选中音色与已应用不一致时查询引擎。
  Future<void> _applyVoice() async {
    try {
      if (_voiceId == null) {
        // 默认音色：清除平台自定义语音并复位中文语言
        _appliedVoiceId = null;
        await _tts.clearVoice();
        await _tts.setLanguage('zh-CN');
        return;
      }
      if (_appliedVoiceId == _voiceId) return;
      final voices = await availableVoices();
      for (final voice in voices) {
        if (voice.key == _voiceId || voice.id == _voiceId) {
          await _tts.setVoice(voice.toVoiceMap());
          _appliedVoiceId = _voiceId;
          return;
        }
      }
      // 引擎无此音色：保持默认
      _appliedVoiceId = null;
    } catch (_) {
      // 音色应用失败不影响播报，回退默认
      _appliedVoiceId = null;
    }
  }
}

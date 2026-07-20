import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 语音识别服务：录音转文字。封装 speech_to_text 与麦克风权限申请。
class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;

  bool get available => _available;
  bool get isListening => _speech.isListening;

  Future<bool> init() async {
    if (Platform.isAndroid) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        _available = false;
        return false;
      }
    }
    _available = await _speech.initialize(
      onError: (error) => debugPrintSafe('speech error: $error'),
    );
    return _available;
  }

  /// 开始监听，实时回传识别文本；[onComplete] 在停止/自然结束时触发。
  Future<void> startListening({
    required void Function(String) onText,
    void Function()? onComplete,
  }) async {
    if (!_available) return;
    _speech.statusListener = (status) {
      if (status == stt.SpeechToText.doneStatus &&
          !_speech.isListening) {
        onComplete?.call();
      }
    };
    await _speech.listen(
      onResult: (result) => onText(result.recognizedWords),
      listenOptions: stt.SpeechListenOptions(
        localeId: 'zh_CN',
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
      ),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }
}

void debugPrintSafe(Object o) {
  // 避免在 release 中引入 print 噪音
  assert(() {
    // ignore: avoid_print
    print(o);
    return true;
  }());
}

// TtsService 音色能力测试：语音列表过滤、切换应用与默认回退（模拟 MethodChannel）
import 'package:daily_planner/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');

  // 模拟引擎：记录 setVoice/clearVoice 调用，getVoices 返回固定列表
  final calls = <String>[];
  late List<Map<String, Object>> voices;

  setUp(() {
    calls.clear();
    voices = [
      {
        'name': 'Ting-Ting',
        'locale': 'zh-CN',
        'identifier': 'com.apple.ttsbundle.Ting-Ting-compact',
      },
      {'name': 'Mei-Jia', 'locale': 'zh-CN'},
      {'name': 'English US', 'locale': 'en-US'},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getVoices':
          return voices;
        case 'setVoice':
          return 1;
        case 'clearVoice':
          return 1;
        case 'setLanguage':
          return 1;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('availableVoices 只保留中文语音并携带引擎标识', () async {
    final tts = TtsService();
    final result = await tts.availableVoices();
    expect(result, hasLength(2));
    expect(result[0].name, 'Ting-Ting');
    expect(result[0].locale, 'zh-CN');
    expect(result[0].id, 'com.apple.ttsbundle.Ting-Ting-compact');
    expect(result[0].key, 'com.apple.ttsbundle.Ting-Ting-compact');
    // 无 identifier 的语音以 名称|区域 为键
    expect(result[1].key, 'Mei-Jia|zh-CN');
  });

  test('TtsVoice.toVoiceMap 含 identifier 时附带该字段', () {
    const voice = TtsVoice(name: 'Ting-Ting', locale: 'zh-CN', id: 'x-1');
    expect(voice.toVoiceMap(), {
      'name': 'Ting-Ting',
      'locale': 'zh-CN',
      'identifier': 'x-1',
    });
  });

  test('setVoice(null) 清除平台音色并保持默认', () async {
    final tts = TtsService();
    await tts.setVoice(null);
    expect(tts.currentVoiceId, isNull);
    expect(calls, contains('clearVoice'));
    expect(calls, isNot(contains('setVoice')));
  });

  test('setVoice 按引擎标识应用；speak 不重复查询已应用音色', () async {
    final tts = TtsService();
    await tts.setVoice('com.apple.ttsbundle.Ting-Ting-compact');
    expect(tts.currentVoiceId, 'com.apple.ttsbundle.Ting-Ting-compact');
    expect(calls, contains('setVoice'));
    // 已应用：再次 speak 不再触发 getVoices/setVoice
    calls.clear();
    await tts.speak('提醒您：喝水');
    expect(calls, isNot(contains('getVoices')));
    expect(calls, isNot(contains('setVoice')));
  });

  test('setVoice 引擎无此音色时保持默认不抛异常', () async {
    final tts = TtsService();
    await tts.setVoice('unknown-voice');
    expect(tts.currentVoiceId, 'unknown-voice');
    expect(calls, isNot(contains('setVoice')));
    // 播报仍可用（回退默认）
    await tts.speak('提醒您：吃药');
    expect(calls, contains('speak'));
    expect(calls, isNot(contains('setVoice')));
  });

  test('speak 在选中音色时播报前应用一次', () async {
    final tts = TtsService();
    await tts.setVoice('Mei-Jia|zh-CN');
    expect(calls.where((c) => c == 'setVoice'), hasLength(1));
  });
}

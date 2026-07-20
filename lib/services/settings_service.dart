import 'package:hive_flutter/hive_flutter.dart';

/// 全局应用设置（当前仅「默认响铃时长」）。基于 Hive 简单 KV 盒，免适配器。
class SettingsService {
  static const String _boxName = 'app_settings';
  static const String _ringKey = 'ringSeconds';
  static const int defaultRingSeconds = 5;

  late final Box _box;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  int get ringSecondsDefault =>
      _box.get(_ringKey, defaultValue: defaultRingSeconds) as int;

  /// 写入默认响铃秒数，限制合理范围 1~600 秒。
  Future<void> setRingSecondsDefault(int value) async {
    final v = value.clamp(1, 600);
    await _box.put(_ringKey, v);
  }
}

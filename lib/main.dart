import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'prompts/prompt_loader.dart';

/// 应用入口：最小化引导，路由守卫见 [App]/[AuthGate]。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动预载语音提示词 YAML（失败静默，云端排期不可用时自动回落本地 NLP）
  unawaited(_preloadPrompts());
  runApp(const App());
}

Future<void> _preloadPrompts() async {
  try {
    await PromptLoader.loadAll();
  } catch (_) {}
}

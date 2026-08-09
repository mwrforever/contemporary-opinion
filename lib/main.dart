import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'app.dart';
import 'prompts/prompt_loader.dart';

/// 安装崩溃落盘钩子：把未捕获的 Flutter/Dart 异常写入应用缓存目录
/// `flutter_error.log`，供 adb run-as 拉取排查。
///
/// 背景：荣耀等机型过滤第三方应用的 INFO 级 logcat，Dart 侧错误（走
/// debugPrint → I/flutter）在 logcat 中不可见，只能靠落盘文件还原现场。
void _installErrorLog() {
  void append(String text) {
    try {
      final file = File('${Directory.systemTemp.path}/flutter_error.log');
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()}\n$text\n\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // 磁盘不可写时静默，不阻断主流程
    }
  }

  // Flutter 框架错误（build/layout/回调阶段）保留默认处理（红屏）并落盘
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    prev?.call(details);
    append('$details');
  };
  // 未捕获异步异常（Zone 外）同样落盘；返回 false 保留默认崩溃行为
  PlatformDispatcher.instance.onError = (error, stack) {
    append('$error\n$stack');
    return false;
  };
}

/// 应用入口：最小化引导，路由守卫见 [App]/[AuthGate]。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 崩溃现场落盘（荣耀机型 logcat 不可见 Dart 日志，见 [_installErrorLog]）
  _installErrorLog();
  // 启动预载语音提示词 YAML（失败静默，云端排期不可用时自动回落本地 NLP）
  unawaited(_preloadPrompts());
  runApp(const App());
}

Future<void> _preloadPrompts() async {
  try {
    await PromptLoader.loadAll();
  } catch (_) {}
}

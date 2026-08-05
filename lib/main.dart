import 'package:flutter/material.dart';

import 'app.dart';

/// 应用入口：最小化引导，路由守卫见 [App]/[AuthGate]。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

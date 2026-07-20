/// 录音采集能力抽象：通过条件导出隔离平台实现。
///
/// - 移动端：`audio_capture_io.dart` —— 封装 `record` 包。
/// - Web 端：`audio_capture_web.dart` —— 委托 `record_web`（已支持 PCM16 流）
///   并额外做安全上下文探测与优雅降级。
///
/// 调用方只需 `AudioCapture()` 即可拿到当前平台的实现，无需关心
/// `dart:html` / 原生插件的差异。两个实现文件都必须导出同名的
/// [AudioCapture] 类（相同公开契约）。
library;

export 'audio_capture_io.dart'
    if (dart.library.html) 'audio_capture_web.dart';

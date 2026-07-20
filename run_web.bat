@echo off
REM ============================================================
REM  时说 (daily_planner) · Flutter Web 启动脚本 (Windows)
REM ============================================================
REM  用法：双击本文件，或在项目根目录命令行运行 run_web.bat
REM  启动后浏览器打开 http://localhost:8080 即可预览效果。
REM
REM  注意：
REM   - 麦克风录音 / 系统通知在 Web 上不可用，App 会自动降级
REM     （录音退回本地识别兜底；通知不生效）。排期 + 冲突检测可正常体验。
REM   - 下面两行是阿里云镜像，非中国大陆环境可删掉。
REM ============================================================

cd /d %~dp0

set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1

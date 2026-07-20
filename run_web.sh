#!/usr/bin/env bash
# ============================================================
#  时说 (daily_planner) · Flutter Web 启动脚本 (macOS / Linux)
# ============================================================
#  用法：chmod +x run_web.sh && ./run_web.sh
#  启动后浏览器打开 http://localhost:8080 即可预览效果。
#
#  注意：
#   - 麦克风录音 / 系统通知在 Web 上不可用，App 会自动降级。
#   - 下面两行是阿里云镜像，非中国大陆环境可删掉。
# ============================================================

cd "$(dirname "$0")"

export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1

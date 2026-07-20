# 项目介绍 · 时说（daily_planner）

> 本文件是项目的「单一事实来源」与进度快照，专为**新会话/新成员接手**编写。
> 最后更新：2026-07-15（主理人：齐活林 / 软件开发团队 SOP）

---

## 0. 一句话定位
**时说** 是一款「用说的就能规划日程」的 Flutter 纯前端移动端 App：语音 → 大模型解析 → 结构化任务 → **冲突检测**（资源冲突标红拦截）。本仓库当前作为 Web 预览 + 演示载体。

- 对外品牌名：**时说（Shí Shuō）**
- 内部包名 / 工程目录名：`daily_planner`（保留为保底资产）
- 目标运行平台：Android / iOS（移动端）；Web 为预览/演示通道

---

## 1. 当前进度快照（2026-07-15）

| 模块 | 状态 | 说明 |
|------|------|------|
| 语音自然规划 | ✅ 已完成 | 云端 `Qwen3-ASR-Flash` 识别 + 本地 `speech_to_text` 兜底 |
| 智能排期 | ✅ 已完成 | 云端 `qwen3.7-max-2026-05-17` 生成结构化任务 |
| 冲突检测 | ✅ 已完成 | 资源占用冲突标红拦截 + 时间重叠弱提醒，3 种手动处理 |
| 离线兜底 | ✅ 已完成 | 未配 key 时退回设备端识别 + 本地中文时间解析 |
| 单元测试 | ✅ 85/85 通过 | `flutter test`；`flutter analyze` 零问题 |
| Web 预览 | ✅ 已完成 | `flutter build web` 成功；已 CloudStudio 静态部署（稳定链接，跨回合不丢）|
| Web 麦克风/通知 | ✅ 已完成 | `audio_capture_web` / `notification_service_web` 条件导入，安全上下文探测 + 优雅降级 |
| 品牌落地 UI | ✅ 已完成 | `splash_screen.dart` 启动页 + 全站品牌名「时说」|
| Git 仓库 | ❌ 未初始化 | 目标远端 `git@github.com:mwrforever/contemporary-opinion.git`（尚未 init/push）|

---

## 2. 功能清单
1. **语音规划**：用户说话 → 阿里云 `Qwen3-ASR-Flash` 语音识别 → `qwen3.7-max` 把口语转写为结构化任务（标题/时间/时长/资源/重复）。
2. **智能排期**：一句话生成排期（如"明早9点开会2小时，用三号会议室，每周一都这样"），无需手填表单。
3. **冲突检测（最大亮点）**：
   - **阻断性冲突 = 资源占用冲突**：同一资源在重叠时段被重复占用（如两场会抢同一间会议室）→ 标红、`pendingConflict` / `effective=false`，默认不生效。
   - **纯时间重叠（资源不同）**：仅琥珀色弱提醒，直接生效。
   - 三种手动处理：改时间 / 换资源 / 确认覆盖已有任务。
4. **离线兜底**：未配置云端 key 时自动退回设备端语音识别 + 本地时间解析（`nlp_parser.dart`），照样可用。

---

## 3. 技术栈
- **框架**：Flutter 3.44 + Dart 3.12
- **状态管理**：Provider
- **本地存储**：Hive（手写 `TypeAdapter` 免 codegen）
- **云端调用**：`http`（DashScope / 私有 MaaS OpenAI 兼容 `/chat/completions`）
- **录音**：`record`（移动端 PCM 采集；Web 端能力受限，见待修复 #2）
- **语音识别（设备端兜底）**：`speech_to_text`
- **语音播报（兜底）**：`flutter_tts`
- **本地通知/铃声**：`flutter_local_notifications` + `flutter_ringtone_player`（移动端；Web 端受限，见待修复 #2）
- **唯一标识**：`uuid`

> 注：原 NLS（`fun-asr-realtime` + `web_socket_channel` + `crypto`）已移除——`Qwen3-ASR-Flash` 与排期模型同属百炼/DashScope，共用一个 API Key。

---

## 4. 目录结构与关键模块
```
lib/
  main.dart                      入口：注入云端服务（未配 key 自动 fallback）
  config/
    aliyun_config.dart           云端配置（baseUrl / 模型名 / 环境变量覆盖）
    secrets.dart                 【gitignore】存放真实 key + 私有 MaaS 端点
  models/
    task.dart                    Task 模型 + ConflictState 枚举 + Hive Adapter(15字段)
  services/
    conflict_detector.dart       冲突检测核心（纯 Dart 可单测，含重复任务展开）
    aliyun_schedule_service.dart qwen3.7-max 排期调用 + parseJson 纯函数
    aliyun_asr_service.dart      Qwen3-ASR-Flash 文件识别（buildWav 纯函数）
    nlp_parser.dart              本地中文时间解析（兜底）
    speech_service.dart          设备端语音识别封装
    tts_service.dart / audio_service.dart / reminder_service.dart  播报/音频/提醒
    task_store.dart              Hive 封装：addWithConflictCheck / recheck / resolveOverride
  screens/
    home_screen.dart             首页任务列表
    add_task_screen.dart         手动加任务（资源/时长字段 + 冲突覆盖按钮）
    voice_input_screen.dart      语音→排期→冲突预览→手动处理
  widgets/
    task_card.dart               任务卡片（冲突红框 + 徽标 + 确认覆盖按钮）
    empty_state.dart / fade_in.dart
  theme/
    app_theme.dart               配色（danger/warn 等）
test/                            conflict_detector / schedule_merge / aliyun_schedule / aliyun_asr / task 等
docs/
  architecture_aliyun.md         阿里云架构 + 冲突检测状态机设计
  aliyun_model_research.md       阿里云模型选型调研
run_web.bat / run_web.sh         本地 Web 预览启动脚本（监听 http://localhost:8080）
```

---

## 5. 云端接入现状
- **端点**：私有 MaaS `https://llm-vpoxw4csmmswi0cm.cn-beijing.maas.aliyuncs.com/api/v1`
  （代码默认值在 `aliyun_config.dart` 的 `baseUrl`；可经环境变量 `DASHSCOPE_BASE_URL` 覆盖）
- **模型**：
  - 排期：`qwen3.7-max-2026-05-17`（默认关闭思考模式 `enable_thinking:false` 以稳定 JSON）
  - 语音识别：`qwen3-asr-flash`
  - 两者经 `/chat/completions` 调用，鉴权 `Authorization: Bearer <key>`
- **密钥存放**：`lib/config/secrets.dart`（已 gitignore，不进版本库）
  - `kDashscopeApiKey`、`kDashscopeBaseUrl`
  - 仍可被环境变量 `DASHSCOPE_API_KEY` / `DASHSCOPE_BASE_URL` / `DASHSCOPE_SCHEDULE_MODEL` / `DASHSCOPE_ASR_MODEL` 覆盖
- ⚠️ **安全**：前端直连 key 仅适合 Demo；生产务必改后端代理。此前 key 曾明文出现在聊天中，建议到阿里云控制台轮换。

---

## 6. 冲突检测设计要点（关键口径）
- `ConflictState { none, pendingConflict, confirmedOverride }`
- `applyDecision()`：若 `hasBlockingConflict`（=资源占用冲突）→ `pendingConflict`/`effective=false`；否则 `none`/`effective=true`
- 此口径保证「改时间 / 换资源 / 确认覆盖」三种手动处理均独立成立、互不矛盾
- 详细状态机见 `docs/architecture_aliyun.md` 第 2.2 节

---

## 7. 问题排查结论（2026-07-15 提出，均已修复）
> 用户 2026-07-15 提出三个问题；经排查，#1 为预览进程退出（非代码 bug），#2/#3 由工程师按 superpowers 流程实现并验证通过。结论如下，供新会话参考。

### 问题 #1（✅ 已修复）：浏览器访问页面空白 / 连接被拒绝（connection refused）
- **根因（已确认）**：本地 `flutter run -d web-server` 预览进程退出，8080 端口无服务监听（非代码 bug）。
- **技术方案**：
  1. 用 `run_web.bat` / `run_web.sh` 重新拉起服务（已设阿里云镜像）；
  2. 若需「分享给他人」而非本机预览，应改用 `flutter build web` 产出静态文件，再起静态服务器（如 `workbuddy_cloudstudio_deploy` 或 `python -m http.server`）；
  3. 在 `run_web` 脚本/文档中明确「dev server 为前台进程，关闭终端即停」。
- **验收**：浏览器打开 `http://localhost:8080` 可见首页（非空白、无连接错误）。

### 问题 #2（✅ 已修复）：Web 端麦克风录音 + 系统通知不可用
- **现状**：`record`（录音）、`flutter_local_notifications`（通知）在 Web 上能力受限或桩实现，导致功能不可用/降级。
- **根因待查（需 systematic-debugging）**：
  - 是浏览器权限/API 限制，还是 `kIsWeb` 下未做适配？
  - Flutter Web 麦克风需走 `dart:html` MediaRecorder / Web Audio API；通知需 `Notification` Web API。
- **技术方案（建议，待工程师确认）**：
  1. 录音：引入 Web 兼容路径——`record` 包若不支持 web，则 `kIsWeb` 分支用 `dart:html` (`MediaRecorder` + `getUserMedia`) 采集 WAV/WebM，转 base64 送 `Qwen3-ASR-Flash`；
  2. 通知：Web 端用 `dart:html` `Notification` API 或 `flutter_local_notifications` 的 web 适配层做权限申请+展示；
  3. 能力探测：无麦克风/无通知权限时优雅降级（提示用户用移动端体验完整能力）。
- **验收**：Web 端能申请麦克风权限并录音识别；能申请通知权限并弹出提醒（或明确降级提示）。

### 问题 #3（✅ 已修复）：品牌名 + 启动页 UI 未落地
- **已锁定品牌（产品经理许清楚交付，2026-07-15）**：
  - 产品名：**时说**；主传播语：**你的时间，不该撞车。**
  - 启动页 Hero：主标题「把脑子里的安排，顺成一天的秩序。」/ 副标题「说出来就好——会听、会排，还会帮你避开每一次撞车。」
  - 卖点：语音规划 / 智能排期 / 冲突检测（三句见 `docs/brand_copy` 或对话记录）
- **技术方案**：
  1. 新增 `screens/splash_screen.dart`（启动页：品牌名 + Hero 文案 + 微动效）；
  2. App 关于页 / 首页标题统一用「时说」替代「每日规划助手」；
  3. 配色沿用 `app_theme.dart`，遵循去饱和单一强调色、完整交互状态、微动效（Taste Skill 规范）；
  4. 设计阶段先用 brainstorming 对齐视觉，再按 superpowers TDD 实现。
- **验收**：App 启动显示「时说」品牌启动页；全站品牌名一致。

---

## 8. 如何运行
```bash
cd D:\code\project\contemporary-opinion
flutter pub get
# 配置密钥（可选，不配则走本地兜底）：编辑 lib/config/secrets.dart
#   kDashscopeApiKey = 'sk-...';  kDashscopeBaseUrl = 'https://.../api/v1'
# 启动 Web 预览
run_web.bat        # Windows
# 或 ./run_web.sh   # Mac/Linux
# 浏览器打开 http://localhost:8080
```
- 依赖镜像：已用 `PUB_HOSTED_URL=https://pub.flutter-io.cn` + `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- Flutter 路径（本机）：`D:\code\flutter\3.44.6\bin\flutter.bat`
- ⚠️ 本机无 Android SDK / 无桌面 admin，仅做了 Dart 层 `analyze`+`test` 与 Web 构建校验，未跑移动端 build。

---

## 9. 已知限制
1. 密钥前端直连仅限 Demo，生产需后端代理。
2. Web 端麦克风/通知已适配（`audio_capture_web` / `notification_service_web`）；受浏览器限制：麦克风需 https/localhost，未来定时通知无法在浏览器调度（移动端承担精确闹钟）。
3. 重复任务冲突检测用近似展开（非完整 RRULE），生产建议精确展开。
4. 模型名依赖私有 MaaS 部署名，若对不上会 4xx（可改 `aliyun_config.dart` 常量或环境变量）。
5. 未做 i18n，当前仅中文。

---

## 10. 仓库与交付
- 本目录**尚未 `git init`**。目标远端：`git@github.com:mwrforever/contemporary-opinion.git`
- 推送前注意：`lib/config/secrets.dart` 已在 `.gitignore`，不会被提交；推送前请确认 key 已轮换。
- 交付报告默认不落盘，需用户明确要求才生成 `deliverables/...`。

---

## 11. 决策记录（避免新会话重复踩坑）
- 模型从 `fun-asr-realtime`+`qwen-plus` → `Qwen3-ASR-Flash`+`qwen3.7-max-2026-05-17`（同属百炼，key 合一，删 NLS 代码）。
- 冲突「阻断口径」定为资源占用冲突（非纯时间重叠），解决三种手动处理自洽问题。
- 品牌名锁定「时说」，纯中文、不加英文名。
- Web 构建实测通过（`flutter build web` 成功），`flutter_local_notifications`/`speech_to_text`/`record` 均有 Web 兼容桩。
- `record` 包 v5 API：`AudioRecorder` + `AudioEncoder.pcm16bits` + `startStream(RecordConfig)`。

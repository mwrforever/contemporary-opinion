# 时说（daily_planner）

> 用说的就能规划日程的语音规划 App。核心价值：**你的时间，不该撞车。**

一款**纯前端** Flutter 移动端 App，帮你用「定时提醒 + 语音解析自动规划 + 冲突检测」把每一天安排得明明白白。无需自建后端，所有数据存放在本地（Hive）；云端大模型为**可选增强**，不配置也能完整使用（自动退回设备端识别 + 本地 NLP 解析）。

---

## 一、项目背景

当代人的日历越来越密：会议、约会、吃药、接孩子、健身……信息散落在脑子、聊天记录和各种 App 里。最痛的不是「记不住」，而是**撞车**——两场会抢同一间会议室、同一辆车被重复占用、重要的事被琐事挤掉。

「时说」想做的事很简单：**张嘴说一句话，日程就自动排好，并且帮你拦下每一次会撞车的安排。** 语音天然比手填表单快，冲突检测天然比人脑可靠。我们希望它「温暖、聪明、不焦虑」——不是又一个冷冰冰的待办清单，而是把脑子里的安排顺成一天的秩序。

---

## 二、目标定位

- **目标用户**：职场人、学生、自由职业者——日程密集、容易被冲突困扰的人。
- **产品调性**：温暖、聪明、不焦虑。
- **一句话价值主张**：**你的时间，不该撞车。**
- **核心卖点**：
  - **语音规划**：张嘴就说，口语秒变结构化任务，不用手填一个字。
  - **智能排期**：一句话自动生成时间、资源、重复规则，排期像说话一样自然。
  - **冲突检测**：会议室被重复占用立刻标红拦下，时间重叠只轻提醒，安排永不出错。

---

## 三、技术栈说明

> 纯前端 Flutter 工程（**不是 Node.js / 没有 package.json**）。所有云端调用经 `http` 走 OpenAI 兼容的 `/chat/completions`，密钥仅作 Demo / 内测用途。

| 能力 | 方案 |
|------|------|
| 开发框架 | Flutter 3.44 + Dart 3.12 |
| 本地存储 | **Hive / Hive Flutter**（纯 Dart，零原生依赖，手写 `TypeAdapter`） |
| 状态管理 | Provider |
| 本地通知 / 精确调度 | `flutter_local_notifications` + `timezone`（移动端，支持系统级精准调度） |
| 响铃 | `flutter_ringtone_player`（调用系统闹钟声，无需附带音频文件） |
| 语音播报 | `flutter_tts`（中文朗读） |
| 设备端语音识别（兜底） | `speech_to_text`（录音转文字） |
| 云端接入 | `http`（DashScope / 私有 MaaS，OpenAI 兼容 `/chat/completions`） |
| 录音采集 | `record` + `record_web`（Web 端麦克风；统一封装为 PCM16 流） |
| Web 平台 API 封装 | `web`（`package:web/web.dart`，替代已废弃的 `dart:html`） |
| 工具 | `intl` / `uuid` / `permission_handler` |

> 排期模型：`qwen3.7-max-2026-05-17`（通义千问，已关闭思考模式 `enable_thinking:false` 以稳定 JSON）。
> 语音识别模型：`qwen3-asr-flash`（百炼文件识别，录完一段→本地封 WAV→base64 经 `input_audio` 传入）。
> 两者**共用同一个 `DASHSCOPE_API_KEY`**，经同一端点调用，未配置则自动退回本地兜底。

---

## 四、核心功能

### 1. 定时提醒 `[已完成]`
- **指定时间**：如「今天下午 3 点开会」。
- **倒计时**：如「30 分钟后吃药」（创建时即折算为绝对时间）。
- **重复提醒**：每天 / 每周（按设定日）/ 工作日 / 自定义星期（如周一三五）。
- 到点通过**系统闹钟声（持续数秒）+ 中文语音播报**双重提醒；应用存活时由 in-app Timer 触发富媒体提醒，应用被杀仍由系统通知兜底。

### 2. 语音解析与自动规划 `[已完成]`
- 录制一段语音 →（云端或设备端）转文字 → 解析为**结构化任务（标题 / 时间 / 时长 / 资源 / 重复）**。
- 云端管线：`qwen3-asr-flash` 识别 + `qwen3.7-max-2026-05-17` 排期。
- 未配置云端 / 云端异常 → 自动退回设备端 `speech_to_text` 识别 + 本地 `nlp_parser` 解析，照常可用。
- 解析结果可勾选确认后再入库。

### 3. 任务管理 `[已完成]`
- 列表查看（全部 / 未完成 / 已完成），点击编辑、左滑删除、勾选完成。
- 手动新增 / 编辑任务（含资源、时长、重复字段）。
- 浅色 / 深色主题自适应（`ThemeMode.system`）。

### 4. 阿里云语音识别 + 大模型排期 + 冲突检测 `[已完成]`
- **云端 ASR**：`qwen3-asr-flash` 文件识别（非实时流式），录完一段本地封 WAV（PCM16@16k 单声道）经 `input_audio` 传入。
- **大模型排期**：`qwen3.7-max-2026-05-17` 把口语转写解析为结构化任务表；云端不可用时退化为本地 NLP 解析。
- **冲突检测**（核心，纯本地、可单测，`lib/services/conflict_detector.dart`）：
  - **时间重叠冲突**：候选任务时段与已有任务时段重叠。
  - **资源占用冲突**：同一资源（如「会议室A」「车」「张经理」）在同一时段被重复占用。
  - **标红 + 默认不生效**：冲突的新任务在预览与列表中**标红显示、默认不生效**（`effective=false`），不进入提醒调度，直到你手动处理。
  - **三种手动处理**（均能让任务生效）：
    - **改时间**：重选日期/时刻，重检后无冲突即生效；
    - **换资源**：改任务所需资源，资源不再被占用即生效；
    - **确认覆盖**：强制生效（即便仍与既有任务重叠）。
  - **未冲突任务正常显示并直接生效**。

> 设计取舍：阻断性冲突判定为「资源被同一时段重复占用」（时间重叠 + 同资源）；纯时间重叠（资源不同）视为弱提醒、不阻断。详见 `docs/architecture_aliyun.md`。

### 5. Web 端适配 `[已完成]`
- **麦克风录音**：通过条件导入 `audio_capture`，移动端用 `record`，Web 端用 `record_web`（MediaRecorder / `getUserMedia`，PCM16 流）；非 `https`/`localhost` 安全上下文时优雅降级并给出提示。
- **系统通知**：通过条件导入 `notification_service`，移动端用 `flutter_local_notifications`，Web 端用 W3C `Notification` API（仅安全上下文 + 已授权时弹即时通知，未来定时调度受浏览器限制）。
- 能力探测逻辑集中在 `lib/services/platform_capabilities.dart`（纯函数，可单测）。

### 6. 品牌启动页「时说」 `[已完成]`
- 启动即展示品牌启动页（`lib/screens/splash_screen.dart`）：声波品牌标识 + 「时说」主标题 + 主/副标语 + 「开始规划」按钮 + 底部主传播语「你的时间，不该撞车。」。
- 详见 `docs/brand_design.md`。

---

## 五、运行方式（重要：本项目是 Flutter，不是 Node.js）

> ⚠️ **用户原话提到的 `npm install && npm run dev` 是错误的**——本项目**没有 `package.json`**，是一个纯 Flutter 工程。正确的等效命令如下。

```bash
# 0. 前置：安装 Flutter 3.12+（本项目实测 3.44.x），并连接 Android / iOS 设备（或模拟器）
flutter --version          # 确认 Flutter 3.12+（Dart 3.12+）

# 1. 拉取依赖
flutter pub get

# 2. 连接设备 / 模拟器后运行
flutter run

# 3. 编译 Android 安装包
flutter build apk --release

# ---- Web 预览（本项目已适配 Web）----
flutter build web --release      # 产出 build/web，可用任意静态服务器托管
# 或开发模式（带热重载）：
run_web.bat        # Windows
# 或
./run_web.sh       # Mac / Linux
# 本地默认监听 http://localhost:8080
```

- 首次运行会请求**麦克风**、**通知**与**精确闹钟**权限，请授权。
- **Web 预览用途**：看 UI / 体验排期 / 冲突检测没问题；但**麦克风需 `https` 或 `localhost` 安全上下文**、**系统通知能力受浏览器限制**（未来定时通知无法在浏览器调度）。完整体验请用移动端。

---

## 六、接入阿里云（可选，纯前端 Demo 方式）

默认**不配置**即为「设备端识别 + 本地解析」模式，开箱即用。排期与语音识别都跑在阿里云百炼 / DashScope 平台，**只需一个 `DASHSCOPE_API_KEY`** 即可同时启用两者：

```bash
# 排期(qwen3.7-max-2026-05-17) 与 语音识别(qwen3-asr-flash) 共用同一个 DashScope API Key
export DASHSCOPE_API_KEY=sk-xxxx

# （可选）覆盖请求基址，默认指向私有 MaaS，形如：
#   https://llm-xxxx.maas.aliyuncs.com/api/v1
# 也可改为公网 DashScope：https://dashscope.aliyuncs.com/compatible-mode/v1
export DASHSCOPE_BASE_URL=https://llm-xxxx.maas.aliyuncs.com/api/v1
```

- 密钥来自 `lib/config/secrets.dart`（**已被 `.gitignore` 忽略，不进版本库**）。仓库已随附模板 `lib/config/secrets.dart.example`，首次克隆后复制并填值即可：

  ```bash
  # 首次克隆后：复制模板 → 填入你的 key 与端点（真实 secrets.dart 请勿提交）
  cp lib/config/secrets.dart.example lib/config/secrets.dart
  ```
  模板内容（占位符）：
  ```dart
  // lib/config/secrets.dart
  const String kDashscopeApiKey = 'sk-xxxx';                 // 占位，替换为你的真实 key
  const String kDashscopeBaseUrl = 'https://llm-xxxx.maas.aliyuncs.com/api/v1';
  ```

- 也可用同名环境变量在运行时覆盖（见 `lib/config/aliyun_config.dart`）：`DASHSCOPE_API_KEY` / `DASHSCOPE_BASE_URL` / `DASHSCOPE_SCHEDULE_MODEL` / `DASHSCOPE_ASR_MODEL`。
- 配置后由 `AliyunConfig.configured` 判定是否启用云端；未配置或调用失败自动本地兜底。

> ⚠️ **安全提示**：把 API Key 打包进前端**仅适合 Demo / 内测**。生产环境应改为「后端 / 云函数代理」持有密钥，前端只拿短期 token，避免泄露与配额盗用。**此前 key 曾明文出现在聊天记录中，建议到阿里云控制台轮换。**

---

## 七、品牌

- 产品名 **「时说」**（对外统一品牌；内部包名 / 工程目录名保留 `daily_planner` 作为保底资产）。
- 主传播语：**你的时间，不该撞车。**
- 启动页设计与色彩 / 字体 / 标识规范见 [`docs/brand_design.md`](docs/brand_design.md)（青绿单色强调 `#0E8C7F`、警示红 `#C0492F`、冲突弱提醒橙 `#C9782B`）。

---

## 八、已知限制

1. **密钥前端直连仅限 Demo**：生产需走后端代理；此前 key 曾明文进聊天，建议轮换。
2. **Web 浏览器不支持未来定时通知调度**：Web 端通知只能即时弹出（由 in-app Timer 触发），无法像移动端那样系统级精准预约未来提醒。
3. **Web 麦克风 / 通知受安全上下文约束**：非 `https` / `localhost` 或无 `getUserMedia` / `Notification` API 时优雅降级，提示用移动端获得完整体验。
4. **应用被杀后的富媒体提醒**：系统通知由系统准时弹出（移动端）；「响铃 + 语音播报」在应用存活时效果最佳，进程被杀仍会收到系统通知，但语音播报可能不自动播放（纯前端平台边界）。
5. **重复任务的冲突判定**为「未来 30 天窗口」近似展开（非完整 RRULE）；超长周期 / 高频重复场景可引入 RRULE 精确展开。
6. **本地 NLP 解析器**为启发式实现，覆盖日常高频句式；极口语化、嵌套或多语言混杂的表述可能需手动校正。
7. **模型名依赖具体部署**：私有 MaaS 部署名若对不上会返回 4xx，可改 `aliyun_config.dart` 常量或环境变量；当前未做 i18n，仅中文。

---

## 九、目录结构

```
lib/
  main.dart                       # 入口：初始化 Hive / 主题 / 通知 / 语音 / 云端服务
  config/
    aliyun_config.dart            # 阿里云接入配置（baseUrl / 模型名 / 环境变量覆盖）
    secrets.dart                  # 【gitignore】存放真实 key + 私有 MaaS 端点（需自行创建）
  theme/
    app_theme.dart                # 全局设计语言（青绿单色强调，浅/深双主题）
  models/
    task.dart                     # 任务模型 + ConflictState 枚举 + 手写 Hive Adapter（15 字段）
  services/
    task_store.dart               # 本地存储（Hive + Provider）+ 冲突感知的入库/重检/覆盖
    conflict_detector.dart        # 冲突检测核心（时间重叠 + 资源占用，纯 Dart 可单测）
    nlp_parser.dart               # 本地中文时间解析器（云端兜底）
    aliyun_schedule_service.dart  # qwen3.7-max-2026-05-17 排期（DashScope OpenAI 兼容）+ 本地兜底
    aliyun_asr_service.dart       # qwen3-asr-flash 文件识别（buildWav 纯函数）+ 设备端兜底
    reminder_service.dart         # 通知调度 + 到点响铃/播报
    audio_service.dart            # 响铃
    tts_service.dart              # 语音播报
    speech_service.dart           # 设备端语音识别封装（speech_to_text）
    audio_capture.dart            # 录音采集抽象（条件导出：移动端 record / Web record_web）
    audio_capture_io.dart         # 移动端实现
    audio_capture_web.dart        # Web 实现（安全上下文探测 + 优雅降级）
    notification_service.dart     # 通知抽象（条件导出：移动端 FLN / Web W3C Notification）
    notification_service_io.dart  # 移动端实现
    notification_service_web.dart # Web 实现（仅即时通知，无未来调度）
    pcm_resampler.dart            # PCM 重采样工具（可单测）
    platform_capabilities.dart    # Web 能力探测纯函数（可单测）
  screens/
    splash_screen.dart            # 品牌启动页「时说」
    home_screen.dart             # 今日任务列表 + 悬浮操作 + 冲突覆盖入口
    add_task_screen.dart         # 手动新增 / 编辑（含资源、时长、确认覆盖）
    voice_input_screen.dart      # 云端语音 → 排期 → 冲突预览 → 手动处理 → 入库
  widgets/
    task_card.dart                # 任务卡片（冲突标红 + 未生效徽标）
    empty_state.dart              # 空状态
    fade_in.dart                  # 入场微动效
docs/
  aliyun_model_research.md        # 阿里云模型选型调研（价格 / 质量 / 推出时间）
  architecture_aliyun.md          # 冲突检测 + 云端管线架构设计
  brand_design.md                 # 品牌视觉规范（色彩 / 字体 / 启动页 / 应用商店文案）
test/
  conflict_detector_test.dart     # 冲突检测单测
  schedule_merge_test.dart        # 任务合并 / 生效判定单测
  aliyun_schedule_test.dart       # 排期 JSON 解析单测
  aliyun_asr_test.dart            # ASR WAV 封装单测
  nlp_parser_test.dart            # 本地解析单测
  pcm_resampler_test.dart         # PCM 重采样单测
  platform_capabilities_test.dart # Web 能力探测单测
  web_adapt_test.dart             # Web 适配单测
  task_test.dart / widget_test.dart
run_web.bat / run_web.sh          # 本地 Web 预览启动脚本（监听 http://localhost:8080）
PROJECT_INTRO.md                  # 项目背景与进度快照
```

---

_产品文档由产品经理许清楚维护；技术栈与功能状态以代码为准。_

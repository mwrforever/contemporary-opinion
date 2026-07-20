# 时说（daily_planner）

> 用说的就能规划日程的语音规划 App。核心价值：**你的时间，不该撞车。**

一款**纯前端** Flutter 应用，包含两大模块：

- **任务模块**：定时提醒 + 语音解析自动规划 + 冲突检测
- **记事本模块**：旅游计划 / 账本 / 购物清单 / 阅读 / 菜谱 / 学习记录 的语音速记与结构化存储

所有数据存放在本地（Hive）；云端大模型（阿里云百炼 / DashScope）为**可选增强**，不配置也能完整使用（自动退回设备端识别 + 本地 NLP 解析）。

---

## 一、功能特性

### 任务模块
- **定时提醒**：绝对时间（「今天下午 3 点开会」）、倒计时（「30 分钟后吃药」，创建即折算绝对时间）、重复（每天 / 每周 / 工作日 / 自定义星期）。移动端经 `flutter_local_notifications` + `timezone` 做系统级精确调度，应用被杀仍弹通知；应用存活时由 in-app Timer 触发响铃 + 中文播报。
- **云端语音识别（ASR）**：`qwen3-asr-flash` 文件识别，录完一段本地封装 WAV（PCM16@16k 单声道）经 `input_audio` 传入；未配置 key / 失败自动退回设备端 `speech_to_text`。
- **大模型智能排期**：`qwen3.7-max-2026-05-17` 把口语转写解析为结构化任务（标题 / 时间 / 时长 / 资源 / 重复 / 备注），关闭思考模式以稳定 JSON；云端不可用时退化为本地 NLP 解析。
- **离线兜底**：`nlp_parser.dart` 支持绝对/相对/模糊时间、重复、资源词抽取；零配置、零费用、离线可用。
- **任务管理**：列表查看（全部 / 未完成 / 已完成），编辑、左滑删除、勾选完成；浅色 / 深主题自适应。
- **冲突检测（核心亮点，纯本地可单测）**：
  - 时间重叠 = 时段相交；资源占用冲突 = 时间重叠且同资源被重复占用。
  - 阻断性冲突（资源占用）→ 候选任务标红、`effective=false`、默认不生效；纯时间重叠（资源不同）仅弱提醒、正常生效。
  - 三种手动处理：改时间 / 换资源 / 确认覆盖。

### 记事本模块
- **六大类记录**：旅游计划、账本、购物清单、阅读、菜谱、学习记录。
- **语音速记**：说一句话 → 大模型按提示词解析为结构化字段，例如：
  - 旅游：出发地（`home_city`）、起止日期（`start_date` / `end_date`）、大交通（`intercity_transport`：方式 / 是否往返）。
  - 账本：收支类型（`type`）、金额（`amount`）。
  - 购物：预期价（`expected_price`）、实付价（`actual_price`）。
  - 阅读 / 菜谱 / 学习记录：标题、进度、时长等单词字段。
- **查看 / 编辑 / 删除**：每条记录可在列表行内或详情页查看，支持编辑与删除。
- **语音预览卡片 + 滑动确认入库**：解析结果先预览，确认后再存入 Hive。
- 同样支持云端 / 本地双链路（解析失败时退回设备端识别 + 本地启发式解析）。

---

## 二、技术栈

> 纯前端 Flutter 工程（**不是 Node.js / 没有 package.json**）。所有云端调用经 `http` 走 OpenAI 兼容的 `/chat/completions`，密钥仅作 Demo / 内测用途。

| 能力 | 方案 |
|------|------|
| 开发框架 | Flutter 3.44 + Dart 3.12 |
| 本地存储 | **Hive / Hive Flutter**（纯 Dart，零原生依赖，手写 `TypeAdapter`） |
| 状态管理 | Provider |
| 本地通知 / 精确调度 | `flutter_local_notifications` + `timezone` |
| 响铃 | `flutter_ringtone_player`（调用系统闹钟声，无需附带音频文件） |
| 语音播报 | `flutter_tts`（中文朗读） |
| 设备端语音识别（兜底） | `speech_to_text` |
| 云端接入 | `http`（DashScope / 私有 MaaS，OpenAI 兼容 `/chat/completions`） |
| 录音采集 | `record` + `record_web`（Web 端麦克风；统一封装为 PCM16 流） |
| Web 平台 API | `web`（`package:web/web.dart`，替代已废弃的 `dart:html`） |
| 提示词解析 | `yaml`（语音解析 prompt 以 YAML 管理） |
| 工具 | `intl` / `uuid` / `permission_handler` |

> 排期模型：`qwen3.7-max-2026-05-17`（关闭思考模式 `enable_thinking:false` 以稳定 JSON）。
> 语音识别模型：`qwen3-asr-flash`（百炼文件识别，录完一段→本地封 WAV→base64 经 `input_audio` 传入）。
> 两者**共用同一个 `DASHSCOPE_API_KEY`**，经同一端点调用，未配置则自动退回本地兜底。

---

## 三、目录结构

```
lib/
  main.dart                       # 入口：初始化 Hive / 主题 / 通知 / 语音 / 云端服务
  config/
    aliyun_config.dart            # 阿里云配置（baseUrl / 模型名 / 环境变量覆盖）
    secrets.dart                  # 【gitignore】真实 key + 私有 MaaS 端点（需自行创建）
  theme/
    app_theme.dart                # 全局设计语言（青绿单色强调，浅/深双主题）
  models/
    task.dart                     # 任务模型 + ConflictState 枚举 + Hive Adapter
    dictionary.dart               # 词典（资源 / 同义词等）
    notebook_trip.dart            # 旅游计划模型
    notebook_ledger.dart          # 账本模型
    notebook_shopping.dart        # 购物清单模型
    notebook_reading.dart         # 阅读记录模型
    notebook_recipe.dart          # 菜谱模型
    notebook_study.dart           # 学习记录模型
  services/
    task_store.dart               # 任务本地存储 + 冲突感知入库/重检/覆盖
    notebook_store.dart           # 记事本各类记录本地存储（Hive）
    conflict_detector.dart        # 冲突检测核心（时间重叠 + 资源占用，可单测）
    nlp_parser.dart               # 本地中文时间解析（云端兜底）
    aliyun_schedule_service.dart  # 大模型排期（含 parseJson 纯函数）+ 本地兜底
    aliyun_asr_service.dart       # 语音识别（qwen3-asr-flash，buildWav 纯函数）
    notebook_voice_service.dart   # 记事本语音解析编排
    reminder_service.dart         # 通知调度 + 到点响铃/播报
    audio_service.dart / tts_service.dart / speech_service.dart  # 音频/播报/识别封装
    audio_capture.dart/.io.dart/.web.dart   # 录音采集（移动端 record / Web record_web，条件导入）
    notification_service.dart/.io.dart/.web.dart  # 通知（移动端 FLN / Web W3C Notification）
    pcm_resampler.dart            # PCM 重采样（可单测）
    platform_capabilities.dart    # Web 能力探测纯函数（可单测）
  screens/
    splash_screen.dart            # 品牌启动页「时说」
    settings_screen.dart          # 设置
  modules/
    tasks/
      tasks_tab.dart              # 任务模块主 tab
      task_list.dart              # 任务列表
      add_task_screen.dart        # 手动新增 / 编辑（含资源/时长/重复/冲突覆盖）
      voice_input_screen.dart     # 语音 → 排期 → 冲突预览 → 手动处理 → 入库
    notebook/
      notebook_tab.dart           # 记事本模块主 hub（六大类入口）
      screens/                    # trip / ledger / shopping / reading / recipe / study 详情页
      widgets/                    # notebook_hub_card / notebook_report / notebook_shared
  widgets/
    task_card.dart / empty_state.dart / fade_in.dart / speed_dial.dart / ...
assets/prompts/                   # 语音解析提示词（tasks_voice_*.yaml + notebook_voice_*.yaml）
docs/                             # 架构设计 / PRD / 类图 / 时序图 / 品牌规范
test/                             # 29 个测试文件（conflict / schedule / asr / nlp / notebook / widget 等）
run_web.bat / run_web.sh          # 本地 Web 预览启动脚本（监听 http://localhost:8080）
```

---

## 四、快速开始

```bash
# 1. 前置：安装 Flutter 3.12+（本项目实测 3.44.x）
flutter --version

# 2. 克隆仓库
git clone git@github.com:mwrforever/contemporary-opinion.git
cd contemporary-opinion

# 3. 拉取依赖
flutter pub get

# 4.（可选）配置云端密钥 —— 不配则走「设备端识别 + 本地解析」开箱即用
cp lib/config/secrets.dart.example lib/config/secrets.dart
#   然后编辑 lib/config/secrets.dart，填入你的 DASHSCOPE_API_KEY 与端点
#   （也可改用环境变量 DASHSCOPE_API_KEY / DASHSCOPE_BASE_URL 覆盖，见下）

# 5. 运行（连接 Android / iOS 设备或模拟器）
flutter run

# Web 预览（已适配 Web，看 UI / 排期 / 冲突检测）
flutter build web --release        # 产出 build/web，可托管为静态站点
# 或开发模式（带热重载）：
run_web.bat        # Windows
# 或
./run_web.sh       # Mac / Linux
# 本地默认监听 http://localhost:8080
```

- 首次运行会请求**麦克风**、**通知**与**精确闹钟**权限，请授权。
- **Web 预览说明**：看 UI / 体验排期 / 冲突检测没问题；但麦克风需 `https` 或 `localhost` 安全上下文、系统通知能力受浏览器限制（未来定时通知无法在浏览器调度）。完整体验请用移动端。

---

## 五、接入阿里云（可选，纯前端 Demo 方式）

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
  cp lib/config/secrets.dart.example lib/config/secrets.dart
  ```

  模板内容（占位符）：
  ```dart
  const String kDashscopeApiKey = 'sk-xxxx';                 // 占位，替换为你的真实 key
  const String kDashscopeBaseUrl = 'https://llm-xxxx.maas.aliyuncs.com/api/v1';
  ```

- 也可用同名环境变量在运行时覆盖（见 `lib/config/aliyun_config.dart`）：`DASHSCOPE_API_KEY` / `DASHSCOPE_BASE_URL` / `DASHSCOPE_SCHEDULE_MODEL` / `DASHSCOPE_ASR_MODEL`。
- 配置后由 `AliyunConfig.configured` 判定是否启用云端；未配置或调用失败自动本地兜底。

> ⚠️ **安全提示**：把 API Key 打包进前端**仅适合 Demo / 内测**。生产环境应改为「后端 / 云函数代理」持有密钥，前端只拿短期 token，避免泄露与配额盗用。

---

## 六、运行测试

```bash
# 全部单元测试（29 个测试文件，覆盖冲突检测 / 排期 / ASR / NLP / 记事本 / 组件）
flutter test

# 静态分析（0 error 为通过，可能有存量 info/warning 风格提示）
flutter analyze
```

---

## 七、品牌

- 产品名 **「时说」**（对外统一品牌；内部包名 / 工程目录名保留 `daily_planner`）。
- 主传播语：**你的时间，不该撞车。**
- 启动页设计与色彩 / 字体 / 标识规范见 [`docs/brand_design.md`](docs/brand_design.md)（青绿单色强调 `#0E8C7F`、警示红 `#C0492F`、冲突弱提醒橙 `#C9782B`）。

---

## 八、已知限制

1. **密钥前端直连仅限 Demo**：生产需走后端代理。
2. **Web 浏览器不支持未来定时通知调度**：Web 端通知只能即时弹出（由 in-app Timer 触发），无法像移动端那样系统级精准预约未来提醒。
3. **Web 麦克风 / 通知受安全上下文约束**：非 `https` / `localhost` 或无 `getUserMedia` / `Notification` API 时优雅降级，提示用移动端获得完整体验。
4. **应用被杀后的富媒体提醒**：系统通知由系统准时弹出（移动端）；「响铃 + 语音播报」在应用存活时效果最佳，进程被杀仍会收到系统通知，但语音播报可能不自动播放（纯前端平台边界）。
5. **重复任务的冲突判定**为「未来 30 天窗口」近似展开（非完整 RRULE）；超长周期 / 高频重复场景可引入 RRULE 精确展开。
6. **本地 NLP 解析器**为启发式实现，覆盖日常高频句式；极口语化、嵌套或多语言混杂的表述可能需手动校正。
7. **模型名依赖具体部署**：私有 MaaS 部署名若对不上会返回 4xx，可改 `aliyun_config.dart` 常量或环境变量；当前未做 i18n，仅中文。

---

## 九、仓库与许可

- **仓库地址**：`git@github.com:mwrforever/contemporary-opinion.git`
- 分支：`main`
- 提交规范：隐私文件（`.workbuddy/`、真实 `secrets.dart`、日志、工具产物）已由 `.gitignore` 排除，不会进版本库。
- 许可证：详见仓库 `LICENSE` 文件（如未添加可后续补充）。

---

_产品文档由产品经理许清楚维护；技术栈与功能状态以代码为准。_

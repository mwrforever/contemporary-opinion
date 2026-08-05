# 开发进度跟踪 · 时说 / daily_planner

> 本文件为**可追溯的进度快照**，由交付总监（齐活林）维护。
> 状态标注采用统一三态：`[已完成]` / `[进行中]` / `[待开始]`。
> 生成日期：2026-07-15。项目位置：`D:\code\project\contemporary-opinion`。

---

## 一、进度概览

| 维度 | 数量 |
|------|------|
| 里程碑任务总数 | 13 |
| `[已完成]` | 12 |
| `[进行中]` | 1（本次迁移文档包）|
| `[待开始]`（待办） | 4 |
| 源文件总数（lib/） | 26 —— 全部 `[已完成]` |
| 测试文件总数（test/） | 10 —— 全部 `[已完成]`（85 项用例通过）|
| `flutter analyze` | ✅ No issues found |
| `flutter test` | ✅ 85 / 85 通过 |

---

## 二、里程碑任务快照

| 编号 | 任务名称 | 所属模块 | 状态 | 完成时间 | 阻塞 / 说明 |
|------|----------|----------|------|----------|----------------|
| M1 | 初始化 Flutter 工程 + Hive 本地存储（手写 TypeAdapter） | 基础设施 | `[已完成]` | 2026-07-14 | — |
| M2 | 定时提醒（绝对时间 / 倒计时 / 重复） | 提醒 | `[已完成]` | 2026-07-14 | 移动端系统通知 + 响铃/播报 |
| M3 | 语音解析自动规划 + 设备端识别兜底（speech_to_text + nlp_parser） | 语音规划 | `[已完成]` | 2026-07-14 | — |
| M4 | 任务管理（CRUD / 列表 / 深浅主题） | 任务 | `[已完成]` | 2026-07-14 | — |
| M5 | 阿里云云端管线 + 冲突检测（时间重叠 + 资源占用） | 云端 / 冲突 | `[已完成]` | 2026-07-15 | 模型经历两次切换（见 M7），最终为 Qwen3-ASR-Flash + qwen3.7-max-2026-05-17 |
| M6 | 冲突标红 + 默认不生效 + 三种手动处理（改时间 / 换资源 / 确认覆盖） | 冲突 | `[已完成]` | 2026-07-15 | — |
| M7 | 模型切换 + 私有 MaaS 端点接入 | 云端 | `[已完成]` | 2026-07-15 | 排期改为 `qwen3.7-max-2026-05-17`；端点改为私有 MaaS；密钥移至 gitignore 的 `secrets.dart` |
| M8 | Flutter Web 构建验证通过 | 构建 | `[已完成]` | 2026-07-15 | 首次 Web 构建成功，移动端专属插件均有 Web 兼容桩 |
| M9 | 品牌命名「时说」+ 启动页 splash_screen | 品牌 | `[已完成]` | 2026-07-15 | 配套 `docs/brand_design.md` |
| M10 | Web 端麦克风录音适配（AudioCapture 条件导入，MediaRecorder/getUserMedia） | Web 适配 | `[已完成]` | 2026-07-15 | 非 https/localhost 优雅降级 |
| M11 | Web 端系统通知适配（NotificationService 条件导入，W3C Notification） | Web 适配 | `[已完成]` | 2026-07-15 | 浏览器不支持未来定时调度 |
| M12 | CloudStudio 静态部署（解决预览连接被拒绝，得到稳定链接） | 部署 | `[已完成]` | 2026-07-15 | 用 `flutter build web` + CloudStudio 沙箱，跨回合不丢 |
| M13 | 项目迁移文档包（README 重写 / FEATURES / PROGRESS / 自包含模板） | 文档 / 迁移 | `[进行中]` | 2026-07-15 | 许清楚撰写 README+FEATURES；主理人撰写 PROGRESS；自包含模板已建 |

---

## 三、阶段 1 重构快照（2026-08-05 起，分支 feat/phase1-core）

| 项 | 状态 | 说明 |
|----|------|------|
| Task 1 依赖重排 | `[已完成]` | 锁最新稳定版（sqflite 2.4.3 / flutter_local_notifications 22.2.0 / permission_handler 13.0.0 / audioplayers 6.8.1 / record 7.1.1 等）；win32 ^5/^6 传递冲突 → share_plus 12.x、package_info_plus 9.x 兼容线 |
| Android 平台配置 | `[已完成]` | 开启 core library desugaring；权限：RECORD_AUDIO / POST_NOTIFICATIONS / SCHEDULE_EXACT_ALARM / WAKE_LOCK / VIBRATE |
| 测试基线 | `[已完成]` | 292 通过；11 项旧 aliyun ASR 转写测试因 record 7.x 升级失效，按计划删除（阶段 2 语音重写） |
| flutter analyze | `⚠️ 0 error / 51 info` | info 主要为过渡期 dev 依赖提示（hive/web/speech/just_audio，Task 10 清理）与存量风格项 |
| debug APK 构建 | `[已完成]` | 2026-08-05 产出 `build/app/outputs/flutter-apk/app-debug.apk`；构建链修复：file_picker→file_selector（其 Android 端 Kotlin 1.8.22 与 AGP 9/Gradle 9 不兼容，产物为空 jar）、app compileSdk=37（permission_handler 13 要求）、`kotlin.incremental=false`（规避增量缓存崩溃）、签名块 DSL 修复（`java.util` 被 Gradle `java` 扩展遮蔽）、sqlite3 原生资产下载需本地代理（`HTTPS_PROXY=127.0.0.1:7897`）注入 |
| 测试基线（更新） | `[已完成]` | 312 通过 / 1 已知遗留失败（`audio_service_test.dart`，Task 14 重写响铃时替换） |
| 环境遗留 | `[部分完成]` | Android SDK 已配置 `D:\code\envs\android\sdk`（API 37 junction `android-37`→`android-37.0` 已建）；开发人员模式已开启；cmdline-tools 组件缺失（不影响构建，可后补）；maven.google.com 偶发瞬时超时 |
| Task 6+7 路由守卫与登录/注册页 | `[已完成]` | 已登录直达主框架（三 Tab：任务/记事本占位 + 我的登出）；未登录品牌页 1.2s 后进登录页；登出回登录页；登录/注册表单校验（必填/密码长度/一致性/唯一）；新增 `test/support/fake_auth_service.dart` 解耦 widget 测试与 FFI 异步 |
| Task 8 设计 Token 落地 | `[已完成]` | `app_theme.dart` 精确色值（accent #0E8C7F 等）、浅深 ColorScheme 显式锁定、文本层级 20/800·16/600·14/400、组件主题（按钮 52/卡片 20/输入框 12/chip 胶囊/导航栏/分段控件）、浅色按钮用 accentStrong 保对比度；`buildAppTheme([Brightness])` |
| Task 9 旧数据迁移 | `[已完成]` | `LegacyMigrationService` + 冻结 `LegacyTask` 适配器（与旧 TaskAdapter 二进制一致）；升级后首个注册用户（通常 id=1）承接旧任务；幂等标记 `app_meta.legacy_migrated`；失败静默；登录后钩子 `onLoggedIn` 注入（生产默认迁移，测试空实现）；记事本旧数据待阶段 3 建表后迁移 |
| Task 10 清理 Web/死代码 | `[已完成]` | 删除 `audio_capture_web/audio_service_web/notification_service_web`、`web/` 目录与 `run_web.bat/.sh`、`test/web_adapt_test.dart`；三个能力抽象改为纯 IO 导出；pubspec 移除 `record_web`/`web`（过渡依赖剩余：hive_ce 至 Task 12、speech_to_text 至 Task 15、just_audio 至 Task 14） |
| Task 11+12 Task 模型/DAO/Store 迁移 SQLite | `[已完成]` | Task 去 Hive（纯 Dart + toMap/fromMap，id 保持 UUID，tasks.id 改 TEXT 主键）；新增 `TaskDao`（user_id 隔离/状态/生效过滤）；`TaskStore` 换 SQLite 实现且对外方法签名不变；删除 Hive 适配器两个旧测试；task_test 移除 Hive round-trip、改由 task_model/task_dao/task_store 新测覆盖 |

---

## 三、待办与阻塞项

| 编号 | 任务名称 | 优先级 | 状态 | 阻塞 / 说明 |
|------|----------|--------|------|----------------|
| P1 | 生产化：后端 / 云函数代理持有密钥 | P1 | `[待开始]` | **阻塞项**：前端直连 API Key 仅限 Demo；需另建后端代理签发短期 token，否则有泄露与配额盗用风险 |
| P2 | RRULE 精确重复任务冲突展开 | P1 | `[待开始]` | 当前为「未来 30 天窗口」近似展开；超长周期需引入 RRULE |
| P3 | 应用商店长描述文案 | P1 | `[待开始]` | 品牌名「时说」已定，长描述未写；可交产品经理续写 |
| P4 | API Key 轮换 | P2 | `[待开始]` | **阻塞项（需用户操作）**：此前一把 key 明文进过聊天，需用户到阿里云控制台禁用/轮换后回填 `secrets.dart` |
| P5 | Web 未来定时通知 | P2 | `[待开始]` | **已知限制（浏览器 API）**：Web Notification 只能在页面存活时即时弹出，无法像移动端那样系统级未来定时；建议移动端承担精确闹钟 |

---

## 四、源文件完整性清单（lib/）

> 全部 `[已完成]`。结构保持原工程不变，可直接运行。

### 入口与配置
| 文件 | 说明 | 状态 |
|------|------|------|
| `lib/main.dart` | 入口：初始化 Hive / 主题 / 通知 / 语音 / 云端服务；标题「时说」+ 启动页路由 | `[已完成]` |
| `lib/config/aliyun_config.dart` | 云端配置（模型名 / 端点，支持环境变量覆盖） | `[已完成]` |
| `lib/config/secrets.dart` | 私密配置（API Key / 端点，已被 .gitignore） | `[已完成]` |
| `lib/theme/app_theme.dart` | 全局设计语言（单色强调，浅/深双主题） | `[已完成]` |

### 模型
| 文件 | 说明 | 状态 |
|------|------|------|
| `lib/models/task.dart` | 任务模型 + 手写 Hive 适配器（含 resource / conflictState / effective / durationMinutes） | `[已完成]` |

### 服务（services/）
| 文件 | 说明 | 状态 |
|------|------|------|
| `lib/services/task_store.dart` | 本地存储（Hive + Provider）+ 冲突感知入库/重检/覆盖 | `[已完成]` |
| `lib/services/conflict_detector.dart` | 冲突检测核心（时间重叠 + 资源占用，纯 Dart 可单测） | `[已完成]` |
| `lib/services/nlp_parser.dart` | 本地中文时间解析器（云端兜底） | `[已完成]` |
| `lib/services/aliyun_schedule_service.dart` | 排期服务（qwen3.7-max-2026-05-17，关闭思考模式）+ 本地兜底 | `[已完成]` |
| `lib/services/aliyun_asr_service.dart` | 语音识别（Qwen3-ASR-Flash 文件识别，WAV base64）+ 设备端兜底 | `[已完成]` |
| `lib/services/audio_capture.dart` | 录音能力抽象（条件导出） | `[已完成]` |
| `lib/services/audio_capture_io.dart` | 移动端录音（record 包） | `[已完成]` |
| `lib/services/audio_capture_web.dart` | Web 端录音（MediaRecorder / getUserMedia） | `[已完成]` |
| `lib/services/pcm_resampler.dart` | PCM 重采样（Web→16k 适配 ASR） | `[已完成]` |
| `lib/services/platform_capabilities.dart` | 平台能力探测纯函数（可单测） | `[已完成]` |
| `lib/services/notification_service.dart` | 通知服务抽象（条件导出） | `[已完成]` |
| `lib/services/notification_service_io.dart` | 移动端通知（flutter_local_notifications） | `[已完成]` |
| `lib/services/notification_service_web.dart` | Web 端通知（W3C Notification） | `[已完成]` |
| `lib/services/reminder_service.dart` | 通知调度 + 到点响铃/播报 | `[已完成]` |
| `lib/services/audio_service.dart` | 响铃（系统闹钟声） | `[已完成]` |
| `lib/services/tts_service.dart` | 语音播报（flutter_tts） | `[已完成]` |
| `lib/services/speech_service.dart` | 设备端语音识别（speech_to_text） | `[已完成]` |

### 界面（screens/）与组件（widgets/）
| 文件 | 说明 | 状态 |
|------|------|------|
| `lib/screens/splash_screen.dart` | 品牌启动页「时说」 | `[已完成]` |
| `lib/screens/home_screen.dart` | 今日任务列表 + 悬浮操作 + 冲突覆盖入口 | `[已完成]` |
| `lib/screens/add_task_screen.dart` | 手动新增 / 编辑（含资源、时长、确认覆盖） | `[已完成]` |
| `lib/screens/voice_input_screen.dart` | 云端语音 → 排期 → 冲突预览 → 手动处理 → 入库 | `[已完成]` |
| `lib/widgets/task_card.dart` | 任务卡片（冲突标红 + 未生效徽标） | `[已完成]` |
| `lib/widgets/empty_state.dart` | 空状态 | `[已完成]` |
| `lib/widgets/fade_in.dart` | 入场微动效 | `[已完成]` |

### 测试（test/，全部 `[已完成]`，85 用例通过）
`conflict_detector_test.dart` · `schedule_merge_test.dart` · `aliyun_schedule_test.dart` · `aliyun_asr_test.dart` · `nlp_parser_test.dart` · `task_test.dart` · `pcm_resampler_test.dart` · `platform_capabilities_test.dart` · `web_adapt_test.dart` · `widget_test.dart`

---

## 五、自包含性核对

| 项目 | 状态 | 说明 |
|------|------|------|
| 依赖声明 `pubspec.yaml` | `[已完成]` | 完整；`flutter pub get` 即可拉齐 |
| 私密配置模板 `lib/config/secrets.dart.example` | `[已完成]` | 占位符模板，首次克隆复制为 `secrets.dart` 并填值；真实 `secrets.dart` 已被 .gitignore |
| Web 启动脚本 `run_web.bat` / `run_web.sh` | `[已完成]` | 已设阿里云镜像，启动 `flutter run -d web-server` |
| 构建产物 `build/web/` | `[已完成]` | 已产出，可直接托管 / CloudStudio 部署 |
| 运行说明 | `[已完成]` | 见 README.md（**注意：本项目是 Flutter，正确命令为 `flutter pub get` + `flutter run`，并非 `npm install`**）|

---

## 六、一键接手指引（新会话）

```bash
cd D:\code\project\contemporary-opinion
flutter pub get
cp lib/config/secrets.dart.example lib/config/secrets.dart   # 填入你的 DASHSCOPE_API_KEY 与端点
flutter run                    # 移动端
# 或 Web 预览：
flutter build web --release   # 产物在 build/web，可托管 / CloudStudio 部署
# 或开发模式：run_web.bat (Windows) / ./run_web.sh (Mac/Linux)
```

> 未配置密钥时 App 自动退回设备端识别 + 本地 NLP 解析，功能不受影响。

---

## 七、模块化重构进度（底部 2-Tab「任务 / 记事本」+ 记事本模块，2026-07-16 ~ 07-17）

> 本轮为「时说」二次重构。UI/UX 重构已完成；模块化（底部 2-Tab + 记事本模块）**编码实现已完成**，`flutter analyze` 0 error、`flutter build web --release` 构建通过（2026-07-17，主理人齐活林直接落地）。

### 7.1 UI/UX 重构（✅ 已完成 · 2026-07-16）
- `lib/theme/app_theme.dart` 重写为统一设计令牌；`task_card.dart` / `home_screen.dart` / `add_task_screen.dart` 组件化重排（设计令牌：青绿 0xFF0F8C7E、danger/warn/ok + Soft 变体、半径 10/14/20、8px 间距、扩散阴影）。
- 验证：`flutter analyze` No issues；`flutter test` 85/85 通过（Flutter 3.44.6 @ D:\code\flutter\3.44.6）。

### 7.2 模块化重构设计决策（用户拍板）
- **手动录入不接任何 LLM**：纯 UI 表单 → 校验 → 落库。`tasks_manual.yaml` / `notebook_manual.yaml` 已删除，不进仓库。
- **语音录入 = 两步 LLM**：① 复用 `AliyunAsrService` 转写；② 按子功能 YAML 提示词结构化。
- **记事本按子功能拆**（非通用 FieldDef 动态表单）：每个子功能一个固定 `voice` YAML 提示词。
- **提示词设计阶段人工逐条批准落地，不建 App 内审批页**（原设置 Tab / 审批页方案已否决）。
- **底部 2-Tab**（任务 / 记事本），无设置 Tab。
- 状态管理沿用 `provider`；唯一新增依赖 `yaml: ^3.1.2`；提示词放 `assets/prompts/`。

### 7.3 记事本子功能语音提示词落地（✅ 设计收尾 · 2026-07-17）
| 文件 | 子功能 | 字段要点 |
|---|---|---|
| `assets/prompts/tasks_voice.yaml` | 任务·语音 | 回写为 agent 模板风格（无 approved 字段） |
| `assets/prompts/notebook_voice_shopping.yaml` | 购物清单 | item / expected_price / actual_price / category / note |
| `assets/prompts/notebook_voice_ledger.yaml` | 收支账本 | title / type(income\|expense) / amount / category / date / note |
| `assets/prompts/notebook_voice_reading.yaml` | 读书清单 | title / author / status / rating / category / note |
| `assets/prompts/notebook_voice_trip.yaml` | 旅游行程 | meta{intercity_transport/hotel} + transports + days[].checkpoints[]（按天排布）；字典不存价格、LLM 不出金额 |
| `assets/prompts/notebook_voice_study.yaml` | 学习/课程笔记（课程层级） | **重构为课程层级**：课程 NotebookCourse{title(必填)/source/status(want\|learning\|done)/progress(0–100)/rating(1–5)/category/note} 持有 records[]；语音在课程子页内解析为本课 StudyRecord{title(必填)/content/rating/note}（课程不由 LLM 输出，记录挂该课程） |
| `assets/prompts/notebook_voice_recipe.yaml` | 菜谱收藏 | name(必填) / category / ingredients(string[]) / steps(string[]) / difficulty(easy\|medium\|hard) / rating(1–5) / note |

> 状态：菜谱收藏 ✅ **已批准**（用户 2026-07-17 确认）；学习/课程笔记 ✅ **已批准（课程层级）**（用户 2026-07-17 确认 `NotebookCourse` 持有 `StudyRecord[]`，语音绑定课程子页、记录直接挂该课程）。七份提示词设计阶段全部闭环。

### 7.4 待办（模块化重构剩余）
- **编码实现**：底部 2-Tab 导航 + 记事本模块（存储 / 服务 / UI / 语音接入）。**当前状态：✅ 已完成（2026-07-17，`flutter analyze` 0 error、`flutter build web --release` 通过）**——已完成：6 个记事本模型（shopping/ledger/reading/trip[含嵌套 transport/hotel/day/checkpoint/billing]/study[NotebookCourse+StudyRecord]/recipe，均带 fromJson/toJson 的 JSON-map Hive 存储）、`services/notebook_store.dart`（六个 `notebook_<sub>` 盒子 + 增删/课程记录挂载/旅游更新）、`services/notebook_voice_service.dart`（复用 `AliyunScheduleService.parseWithPrompt` 按子功能解析，含 trip 单嵌套对象特例）、`main.dart` 清理旧 `models/notebook.dart` 与三个死适配器并接入 `NotebookVoiceService(schedule:)` + 提供 `NotebookStore` Provider、`modules/notebook/` 六子功能 UI（记事本网格 + 购物/账本/读书/菜谱/旅游详情 + 学习课程两级列表/详情，语音绑定课程子页）。期间修复的关键坑：① 模块文件相对导入深度 `../../`→`../../../`；② `BorderSide`→`Border.all`；③ 旧 `PromptDef.approved/content/system` API 移除后的连带修复（`voice_input_screen`、`prompt_loader` 删 `manual` 枚举）。后续可补：tasks/voice 界面 Taste V1 细节打磨、回归测试。
- **文档回刷**：`docs/system_design.md` 清掉 manual 提示词 / 设置 Tab / 审批页 / 通用 FieldDef 记事本旧方案，对齐本轮子功能模块化 + 2-Tab（2026-07-17 已完成，主理人齐活林兜底回刷）；并同步新增 study/recipe 两个子功能（记事本共 **6 个子功能**：购物/账本/读书/旅游/学习/菜谱，对应 7 个 voice YAML 含 tasks_voice）。PROGRESS 本章同步更新。
- **原 App 生产化遗留**（见第五节）：后端代理密钥（P1）、RRULE 精确重复（P1）、API Key 轮换（P2，需用户到阿里云控制台操作）。

### 7.5 增量修复（Tasks 首页重做 + 记事本旅游打卡点增删改 + 日期 DatePicker + hub 视觉重做）✅ 已完成 · 2026-07-17

> 依据 `docs/system_design_incremental.md` + 用户两项拍板决策（A 垃圾桶清空已完成+确认；B 单加号 FAB / hub 去加号、不加语音入口）。工程师寇豆码（software-engineer）批量落地 T01–T05。

| 任务 | 内容 | 关键文件 | 验收 |
|---|---|---|---|
| T01【P0】 | Tasks 首页：单加号 FAB（展开手动/语音，手动在前）+ 居中滑动筛选 Tab（全部/进行中/已完成，accentSoft pill 随动指示器） | `tasks_tab.dart` / `task_list.dart`(新增 `FilterTabBar`) / `speed_dial.dart`(标签改「手动录入」「语音录入」) | 仅一个 + FAB；滑动筛选无跳变；`TaskFilter.active` 文案改「进行中」 |
| T02【P0】 | 垃圾桶→清空已完成+确认弹窗（决策 A） | `tasks_tab.dart` / `widgets/confirm_dialog.dart`(新增 `ConfirmDialog.show`，AlertDialog + `AppTheme.danger` 确认按钮) | 点垃圾桶弹确认框；确认后遍历 done：先 `reminder.cancelTask(t)` 再 `store.delete(t)`；无 done 时图标 `onPressed:null` 禁用 |
| T03【P1】 | 记事本 hub 视觉重做（去加号，决策 B2/B3） | `notebook_tab.dart` / `widgets/notebook_hub_card.dart`(新增 `NotebookHubCard`) | 2 列网格、更大精致图标容器、透气排版、发丝边框+扩散阴影；无加号；点击进子功能页 |
| T04【P0】 | 旅游打卡点增删改 UI + `updateTrip` 持久化（R3） | `screens/trip_detail.dart`(`_TripDrillDown` 改 StatefulWidget 持 `_trip` 副本 + `_CheckpointEditSheet` + 每天「+ 打卡点」+ 行程「+ 添加一天」+ 删除轻确认) / `models/notebook_trip.dart`(加 `copyWith` + `kTransportModes`/`kBillingTypes`) | 按天增/改/删打卡点（名称/Switch/交通 chip 单选/计费 chip 多选/StarsRow/备注），`copyWith`+`updateTrip`+`setState`；空 days 兜底建 `未排天`；与语音数据共存 |
| T05【P1】 | 旅游/账本日期 DatePicker（R4） | `widgets/notebook_shared.dart`(新增 `DateField`) / `screens/trip_detail.dart`(`_TripAddSheet` 起止日期) / `screens/ledger_detail.dart`(`_LedgerAddSheet` 日期) | 点击弹原生 `showDatePicker`，回填 `yyyy-MM-dd`，复用 `AppTheme` 输入框样式 |

- **验证全绿**：`flutter analyze` **0 error**（剩 16 条 style/info 警告，均为既有代码 `curly_braces`/`unnecessary_underscores` 风格，不影响编译）；`flutter build web --release` 成功（`√ Built build\web`，WASM dry-run 仅 flutter_tts JS-interop 警告，不阻断 JS 构建）；`flutter test` **85/85 全部通过**（Flutter 3.44.6 @ D:\code\flutter\3.44.6）。
- **设计令牌纪律**：全部新/改 UI 复用 `AppTheme`（accent/accentSoft/danger/radius/space/elevation），未自创配色/圆角/阴影；枚举取值与日期格式 `yyyy-MM-dd` 严格对齐 `assets/prompts/notebook_voice_trip.yaml` 与 §7 约定。
- **相对导入深度**：`lib/modules/notebook/screens/*` 与 `widgets/*` 引用 `lib/` 顶层用 `../../../`，同目录用 `./`/`../`，已正确（无 `../../` 不足坑）。
- **实现说明**：`FilterTabBar` 自持 `TabController`（随生命周期创建/释放，更内聚；与类图中 FilterTabBar 组合 TabController 一致），而非由 `TasksTab` 持有——属类图契约内的合理实现选择。`ConfirmDialog` 统一封装破坏性确认，T02 清空与 T04 删除打卡点均复用。

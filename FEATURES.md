# 功能需求清单（时说 / daily_planner）

> 本清单基于 `lib/` 下真实代码核对（以代码为准，非 PRD 设想）。
> 状态图例：`✅ 已完成` / `🔄 进行中` / `⏳ 待开始`。
> 优先级：P0 = 核心已交付；P1 = 重要增强；P2 = 锦上添花 / 运营。

---

## P0 · 核心已交付（全部 ✅ 已完成）

### F01 · 定时提醒 `[✅ 已完成]` · P0
- **描述**：支持绝对时间（如「今天下午 3 点开会」）、倒计时（如「30 分钟后吃药」，创建时折算为绝对时间）、重复（每天 / 每周 / 工作日 / 自定义星期）。移动端经 `flutter_local_notifications` + `timezone` 做系统级精确调度（`exactAllowWhileIdle`），应用被杀仍弹通知；应用存活时由 in-app Timer 触发响铃 + 中文播报。
- **实现**：`lib/services/reminder_service.dart`、`lib/screens/add_task_screen.dart`。

### F02 · 云端语音识别（ASR）`[✅ 已完成]` · P0
- **描述**：`qwen3-asr-flash`（百炼文件识别）把录音转文字——录完一段 → 本地封装 WAV（PCM16@16k 单声道）→ base64 经 `input_audio` 传入 `/chat/completions`。未配置 key / 调用失败自动退回设备端 `speech_to_text`。
- **实现**：`lib/services/aliyun_asr_service.dart`（`buildWav` 纯函数可单测）。

### F03 · 大模型智能排期 `[✅ 已完成]` · P0
- **描述**：`qwen3.7-max-2026-05-17` 把口语转写解析为结构化任务表（标题 / 时间 / 时长 / 资源 / 重复 / 备注），关闭思考模式以稳定 JSON。云端不可用时退化为本地 NLP 解析。
- **实现**：`lib/services/aliyun_schedule_service.dart`（`parseJson` 纯函数可单测）。

### F04 · 离线兜底（本地 NLP 解析）`[✅ 已完成]` · P0
- **描述**：`nlp_parser.dart` 支持绝对时间、相对时间（倒计时）、重复、模糊时间（大后天等）与资源词抽取；未明确时间的任务进入「待安排」。零配置、零费用、离线可用，与云端排期输出同一套结构化任务，可平滑互切。
- **实现**：`lib/services/nlp_parser.dart`。

### F05 · 任务管理（CRUD / 列表 / 深浅主题）`[✅ 已完成]` · P0
- **描述**：今日任务列表（全部 / 未完成 / 已完成筛选）；点击编辑、左滑删除、勾选完成；手动新增 / 编辑（含资源、时长、重复字段）；浅色 / 深色主题自适应（`ThemeMode.system`）。数据持久化于 Hive。
- **实现**：`lib/screens/home_screen.dart`、`lib/screens/add_task_screen.dart`、`lib/services/task_store.dart`、`lib/theme/app_theme.dart`。

### F06 · 冲突检测（时间重叠 + 资源占用）`[✅ 已完成]` · P0
- **描述**：纯本地、可单测的双重检测。时间重叠 = 时段相交；资源占用冲突 = 时间重叠且同资源被重复占用。阻断性冲突（资源占用）→ 候选任务标红、`pendingConflict` / `effective=false`、默认不生效；纯时间重叠（资源不同）仅弱提醒、正常生效。三种手动处理：改时间 / 换资源 / 确认覆盖。重复任务按未来 30 天窗口展开（近似）。
- **实现**：`lib/services/conflict_detector.dart`、`lib/models/task.dart`、`lib/screens/voice_input_screen.dart`、`lib/screens/add_task_screen.dart`。

### F07 · Web 端麦克风录音适配 `[✅ 已完成]` · P0
- **描述**：通过条件导出 `audio_capture`，移动端用 `record`、Web 端用 `record_web`（PCM16 流，封装 `getUserMedia` / MediaRecorder）；非安全上下文（`https`/`localhost`）时抛出友好降级文案，不崩。
- **实现**：`lib/services/audio_capture.dart`、`audio_capture_io.dart`、`audio_capture_web.dart`、`platform_capabilities.dart`。

### F08 · Web 端通知适配 `[✅ 已完成]` · P0
- **描述**：通过条件导出 `notification_service`，移动端用 `flutter_local_notifications`、Web 端用 W3C `Notification` API。Web 端仅能在安全上下文 + 已授权时弹即时通知，无法做未来时间调度（由 in-app Timer 触发后即时弹窗兜底）。
- **实现**：`lib/services/notification_service.dart`、`notification_service_io.dart`、`notification_service_web.dart`。

### F09 · 品牌启动页「时说」`[✅ 已完成]` · P0
- **描述**：启动即展示品牌启动页：声波标识 + 「时说」主标题（52/800/字距4）+ 主/副标语 + 「开始规划」按钮 + 底部主传播语「你的时间，不该撞车。」。品牌视觉见 `docs/brand_design.md`。
- **实现**：`lib/screens/splash_screen.dart`。

---

## P1 · 重要增强（⏳ 待开始）

### F10 · 生产化后端代理密钥 `[⏳ 待开始]` · P1
- **描述**：当前前端直连 DashScope（key 打包进客户端），仅限 Demo / 内测。生产需改为「后端 / 云函数代理」持有密钥，前端只拿短期 token，避免泄露与配额盗用。
- **关联**：此前 key 曾明文出现在聊天记录，建议在落地后端代理前先到阿里云控制台轮换。

### F11 · RRULE 精确重复冲突展开 `[⏳ 待开始]` · P1
- **描述**：当前 `conflict_detector` 对重复任务按「未来 30 天窗口」近似展开，超长周期 / 高频重复场景可能漏检。建议引入标准 RRULE 做精确展开，覆盖任意周期与例外规则。

### F12 · 应用商店长描述 `[⏳ 待开始]` · P1
- **描述**：补齐应用商店上架所需的「长描述」（功能详解、截图文案、关键词、隐私说明等）。注：`docs/brand_design.md` §7 已有一版约 110 字的应用商店**简介**（短描述），可作为长描述的开篇素材，但完整长描述尚未撰写。

---

## P2 · 锦上添花 / 运营（⏳ 待开始）

### F13 · 多语言（i18n）`[⏳ 待开始]` · P2
- **描述**：当前仅中文。面向更广泛分发时引入 `intl` 国际化，至少支持中英双语与文案抽取。

### F14 · 桌面端与系统小组件 `[⏳ 待开始]` · P2
- **描述**：扩展至 macOS / Windows / Linux 桌面端（需补齐各平台录音 / 通知适配），并探索 Android / iOS 主屏 Widget 小组件，让用户无需打开 App 即可见当日安排与冲突提醒。

---

## 状态汇总

| 优先级 | 功能数 | 状态分布 |
|--------|--------|----------|
| P0 | 9 | 9 × ✅ 已完成 |
| P1 | 3 | 3 × ⏳ 待开始 |
| P2 | 2 | 2 × ⏳ 待开始 |
| **合计** | **14** | ✅ 9 · 🔄 0 · ⏳ 5 |

> 说明：本次核对未发现「半吊子」功能——所有标注 ✅ 的能力在代码中均有完整实现；因此本清单不含 `🔄 进行中`。若后续迭代中出现部分完成项，请如实补标。

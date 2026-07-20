# 架构设计文档：阿里云语音→排期 + 冲突检测

- **日期**：2026-07-15
- **负责人**：架构师高见远（本环境具名子智能体未注册，由主理人齐活林代笔）
- **前置依据**：`docs/aliyun_model_research.md`（模型选型）
- **确认方案**：语音识别 `Qwen3-ASR-Flash`（百炼/DashScope）+ 排期生成 `qwen3.7-plus`（百炼/DashScope）+ **纯前端直连**（Demo 最快）。两者同属百炼平台，共用同一个 `DASHSCOPE_API_KEY`。

---

## 一、总体数据流

```
麦克风录音
   │  (record 采集 PCM16@16k mono，录完封 WAV)
   ▼
[阿里云 ASR] Qwen3-ASR-Flash  (DashScope OpenAI 兼容 /chat/completions, input_audio base64)
   │  转写文本 transcript
   ▼
[阿里云排期] qwen3.7-plus  (DashScope OpenAI 兼容 /chat/completions, JSON 输出, 关闭思考模式)
   │  结构化任务表 ScheduledTask[]  (标题/时间/时长/资源/重复)
   ▼
[本地 fallback] NlpParser  (当云端不可用/返回异常时退化)
   │  Task 候选列表
   ▼
[冲突检测] ConflictDetector.detect(candidate, existing)
   │  ConflictResult { timeConflicts, resourceConflicts }
   ▼
预览界面：冲突任务标红 + 默认不生效(pendingConflict / effective=false)
          未冲突任务正常显示 + 直接生效(effective=true)
   │  用户手动调整（改时间 / 换资源 / 确认覆盖）
   ▼
TaskStore.addWithConflictCheck → Hive 持久化 + ReminderService 调度
```

> **接入安全提示**：纯前端直连会把 DashScope API Key 打包进 App，仅适合 Demo / 内测。
> 生产环境应在「云函数 / 后端」代理转发（见文档末尾），避免 Key 泄露与配额盗用。

---

## 二、冲突检测设计（核心）

### 2.1 状态机

每个任务新增两个字段（`lib/models/task.dart`）：

| 字段 | 类型 | 含义 |
|------|------|------|
| `conflictState` | `ConflictState` | `none` / `pendingConflict`（冲突待处理）/ `confirmedOverride`（已确认覆盖） |
| `effective` | `bool` | 是否真正生效（参与提醒调度）。冲突待处理时为 `false` |
| `resource` | `String?` | 所需资源（如「会议室A」「车」「张经理」），用于资源占用冲突 |
| `durationMinutes` | `int` | 任务时长（分钟），默认 60；冲突按「时段」而非「时刻」判断 |

状态流转：

```
         新任务无冲突
   ┌──────────────────────────────► none (effective=true)
   │
新建/导入 ──► detect()
   │
   │  hasConflict == true
   ▼
pendingConflict (effective=false, 标红)
   │
   ├─ 用户「改时间」且重检无冲突 ──► none (effective=true)
   ├─ 用户「换资源」且重检无冲突 ──► none (effective=true)
   └─ 用户「确认覆盖」 ───────────► confirmedOverride (effective=true)
```

### 2.2 算法

`ConflictDetector.detect(Task candidate, List<Task> existing, {DateTime referenceNow, Duration lookahead, Duration? candidateDuration})`

1. **排除项**：`existing` 中 `status == done` 的任务视为已完成、不占资源，不参与冲突。
2. **无时间任务**：`scheduledTime == null` 的 backlog 任务无法定位时段，不参与冲突（返回无冲突）。
3. **时段重叠**：两任务 `[start, start+duration)` 重叠 ⟺ `a.start < b.end && b.start < a.end`。
4. **重复展开**：对 `repeat != none` 的任务，在 `[referenceNow, referenceNow + lookahead(默认30天)]` 窗口内展开其所有发生时刻（`daily`/`weekdays`/`weekly`/`custom`），与候选的每次发生做两两重叠判定。
5. **资源占用冲突**：在「时间已重叠」的前提下，若 `candidate.resource` 与 `existing.resource` 归一化（去空格、小写）后相等且均非空，则记为资源占用冲突（是时间冲突的子集）。

输出 `ConflictResult { List<Task> timeConflicts; List<Task> resourceConflicts; }`，
`hasConflict = timeConflicts.isNotEmpty || resourceConflicts.isNotEmpty`。

> 归一化：`_normResource` 对空/纯空白返回 `null`，否则 `trim().toLowerCase()`，保证「会议室A」与「会议室 a」视为同一资源。

#### 2.2.1 阻断（标红 / 默认不生效）的判定口径

为让「改时间 / 换资源 / 确认覆盖」三种手动处理都成立，采用如下自洽口径：

- **阻断性冲突 = 资源被同一时段重复占用**（时间重叠 + 同资源）。这是唯一触发标红 / `effective=false` / 默认不生效的条件。
- **纯时间重叠（资源不同，如两个会议在不同会议室同时开）= 弱提醒**，不阻断、任务照常生效，仅在预览界面给出琥珀色提示。

理由：若把「任意时间重叠」都判为阻断，则「换资源」永远无法单独消除冲突（时间重叠仍在），与需求中「重新分配资源」这一处理路径矛盾。此口径下三种处理均可独立生效：

| 处理动作 | 结果 |
|----------|------|
| 改时间（避开所有重叠时段） | 重新检测无冲突 → 生效 |
| 换资源（改用未被占用的资源） | 资源不再冲突 → 生效 |
| 确认覆盖 | 强制 `confirmedOverride` → 生效 |

### 2.3 与 TaskStore 的协作

- `addWithConflictCheck(Task, {DateTime? now})`：入库前对候选跑 `detect`，自动写 `conflictState`/`effective`，再 `put`。
- `recheck(Task)`：手动改时间/换资源保存后，对「除自己外」的 `all` 重跑 `detect`；若无冲突则置 `none`/`effective=true`。
- `resolveOverride(Task)`：置 `confirmedOverride`/`effective=true`。

---

## 三、云端服务设计

### 3.1 排期服务 `AliyunScheduleService`（qwen3.7-plus）

- 端点：`POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`
- 头：`Authorization: Bearer <DASHSCOPE_API_KEY>`、`Content-Type: application/json`
- 体：`model: qwen3.7-plus`、`response_format: { type: "json_object" }`、低 `temperature`、
  `enable_thinking: false`（qwen3.7-plus 默认开启思考模式，排期场景需稳定 JSON 故关闭），
  system 指令描述 JSON schema，user 携带「转写文本 + 现有任务（标题/时间/资源）上下文」。
- 解析：将模型 JSON 映射为 `ScheduledTask(title, scheduledTime, durationMinutes, resource, repeat, customWeekdays, note)`。
- **Fallback**：网络异常 / 非 200 / JSON 非法 → 退化到本地 `NlpParser.parse`（保留离线可用）。
- 依赖：`http` 包。

### 3.2 ASR 服务 `AliyunAsrService`（Qwen3-ASR-Flash）

- 协议：DashScope OpenAI 兼容 `/chat/completions`，音频以 `input_audio` 的 base64 Data URL（`data:audio/wav;base64,...`）传入，属「录完一段再识别」的文件识别（非实时流式）。
- 音频采集：`record` 包录制 16kHz 单声道 PCM16，本地封装为标准 WAV 头后 base64（`buildWav` 纯函数）。
- 鉴权：仅需 `DASHSCOPE_API_KEY`（与 3.1 排期服务同一 key），无 NLS / RAM AccessKey / token 等额外字段。
- 参数：`asr_options: { enable_itn: false, language: "zh" }`。
- **Fallback**：未配置 key 或连接失败 → 退回本地 `SpeechService`（设备端识别），保证 Demo 永远可录音。
- 依赖：`http`、`record`。

---

## 四、文件改动清单

| 文件 | 改动 |
|------|------|
| `lib/models/task.dart` | 新增 `ConflictState` 枚举 + `resource`/`conflictState`/`effective`/`durationMinutes` 字段；`TaskAdapter` 字段 11→15 |
| `lib/services/conflict_detector.dart` | **新增**：冲突检测核心（纯 Dart，可单测） |
| `lib/services/aliyun_schedule_service.dart` | **新增**：qwen3.7-plus 排期（关闭思考模式）+ fallback |
| `lib/services/aliyun_asr_service.dart` | **新增**：Qwen3-ASR-Flash 文件识别（WAV base64）+ fallback |
| `lib/services/task_store.dart` | 新增 `addWithConflictCheck` / `recheck` / `resolveOverride` |
| `lib/screens/voice_input_screen.dart` | 重构：云端管线 + 冲突预览/标红/手动调整 |
| `lib/screens/add_task_screen.dart` | 新增 resource / duration 输入；保存后 `recheck` |
| `lib/screens/home_screen.dart` | 传递冲突解析入口 |
| `lib/widgets/task_card.dart` | 冲突任务红框 + 「冲突·未生效」徽标 |
| `lib/theme/app_theme.dart` | 复用 `danger` 作冲突色 |
| `lib/main.dart` | 注入 `AliyunConfig`（apiKey 等，来自环境变量/配置文件） |
| `pubspec.yaml` | 新增 `http` / `record`（移除 `web_socket_channel` / `crypto`） |
| `test/conflict_detector_test.dart` | **新增**：冲突检测单测 |
| `test/schedule_merge_test.dart` | **新增**：任务合并/生效判定单测 |

---

## 五、生产化建议（Demo 之外）

1. **密钥代理**：把 DashScope Key 放后端 / 云函数，前端换短期 token；前端只持有 token。
2. **配额与降级**：监控 429；超额自动切本地 `NlpParser`，保证无网/限流可用。
3. **的资源本体**：Demo 用自由文本 `resource`；生产可接入资源台账（会议室/车辆 CRUD）做强校验。
4. **重复任务冲突**：当前按「未来 30 天窗口」展开近似判定；高频重复场景可引入 RRULE 精确展开。

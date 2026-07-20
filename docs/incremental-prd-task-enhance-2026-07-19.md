# 增量 PRD：任务参数提取与生效 + 标题智能提炼 + UI 交互强化

> 文档版本：v1.0 · 日期：2026-07-19 · 作者：许清楚（产品经理）
> 项目路径：`D:\code\project\contemporary-opinion`（已有 Flutter 项目，纯增量，不重写既有模块）
> 配套文档：`docs/incremental-prd-2026-07-19.md`（前序增量）、`docs/architecture_aliyun.md`

---

## 0. 范围与约束

- **本文仅描述增量变更**，不重写已有模块；新界面/改动均复用既有设计与组件（`AppTheme` / `NotebookChip` / `AlertDialog` 等）。
- 技术栈沿用：Hive（手写 `TaskAdapter`，JSON-map 存储）、Provider、语音双路径（云端 `AliyunScheduleService` + 本地 `NlpParser` 回退）。
- **任务模块必须同时覆盖两条解析路径**：①云端（通义千问 DashScope）②本地 `NlpParser` 回退。两条路径在「参数提取集合」「标题不含参数」上行为须一致。
- 优先级：P0 必须 / P1 重要 / P2 可选增强。每条带【验收标准】。

---

## 1. 产品目标（一句话）

让语音录入**完整、准确**地提取并应用用户说的全部任务参数（提醒时间 / 资源 / 时长 / 重复 / 响铃 / 倒计时），生成**不含参数的语义标题**，并配以更精致、3 秒消失的操作反馈、记事本居中布局与滑动删除二次确认。

---

## 2. 用户故事

**块一 · 参数提取与生效**
- 作为用户，我说「明天下午 3 点开会，用会议室 A，大概 1 小时」，系统应自动填好：时间 15:00、资源=会议室A、时长 60 分钟，无需我再去手动改。
- 作为用户，我说「**每天早上 8 点**背单词」，系统应自动判定这是**重复任务（每天）**、首次提醒今天/次日 08:00，而不需要我额外说"重复"二字。
- 作为用户，我说「每周一、三健身，每次 90 分钟」，系统应判定 custom 重复 + 周一三五、时长 90 分钟。
- 作为用户，我说「10 秒后去倒垃圾」，系统应给出 10 秒倒计时提醒，且资源/时长等未提及项保持默认、不臆造。

**块二 · 标题智能提炼**
- 作为用户，我说「设置提醒时间为 10 秒，去健身房练腿」，任务标题应是「去健身房练腿」，**不含"10秒/提醒时间"等参数文本**，一眼看懂要做什么。
- 作为用户，我说「每天早上 8 点背单词」，标题应是「背单词」而非「每天早上 8 点背单词」。

**块三 · UI 与交互强化**
- 作为用户，我删除/创建任务后，屏幕底部出现一张**精致的操作反馈卡片**（成功/已删除/可撤销），约 3 秒后**带滑出淡出动效**自然消失。
- 作为用户，我在记事本首页看到六大功能入口（图标 + 名称 + 条数）**居中排列**，而不是统统靠左。
- 作为用户，我左滑想删任务时，先弹**确认卡片**让我二次确认，避免误删；取消则卡片回弹不动。

---

## 3. 现状确认（读代码关键发现）

| # | 发现 | 位置 | 影响 |
|---|------|------|------|
| F1 | **任务模型字段已覆盖全部语音可设参数**：`repeat`@4、`customWeekdays`@5、`resource`@11、`durationMinutes`@14、`ringSeconds`@15、`countdownSeconds`@16。Hive 最大索引=16。 | `lib/models/task.dart` | **本增量无需新增 Hive 字段**；工作是把它们"填实"（prompt + 本地解析 + 透传），而非加字段 |
| F2 | 云端排期实际用的是 `_callModel` **内联** system prompt；YAML `tasks_voice.yaml` 虽被 `PromptLoader` 加载但**未被云端路径消费**，两源不一致。 | `aliyun_schedule_service.dart` L142-191；`voice_input_screen.dart` L92 | 改 prompt 必须改对地方，否则无效（前序 PRD 已定"替换内联 prompt"目标） |
| F3 | 云端内联 prompt 已要 `remind_in_seconds/minutes`，但 YAML **无倒计时字段、无 `ring_seconds`、无标题提炼规则、重复仅显式关键词**。 | `tasks_voice.yaml` L20 | 云端 YAML 路径缺倒计时/响铃/标题规则 |
| F4 | `ScheduledTask` **无 `ringSeconds` 字段**；`toTask` 未写 `ringSeconds`；`_fallback` 丢弃 `resource` 且 `durationMinutes` 硬编码 60。 | `aliyun_schedule_service.dart` L10-49, 193-204 | 语音产出的响铃/资源/真实时长在云端或回退时被丢 |
| F5 | 本地 `NlpParser` **不抽取 resource、不抽取 durationMinutes**，`ParsedTask` 也无这两字段；重复判定仅显式关键词（`每天/工作日/每周/周一三五`）。 | `lib/services/nlp_parser.dart` L4-24, 117-131 | 本地回退路径无法产出资源/时长，与云端契约不齐 |
| F6 | 本地 `_extractCorePurpose` 已剥离时间/提醒/重复词生成核心标题（如「每天早上 8 点去跑步」→「去跑步」），**不含参数文本**。 | `nlp_parser.dart` L337-363 | 标题去参基线已具备，需与云端对齐 |
| F7 | 操作反馈：`tasks_tab._showUndo` 用默认 `SnackBar`，**duration 5s + 兜底定时器 5s**；`voice_input_screen._confirm` 弹默认 SnackBar 后**立即 pop**，snackbar 不可见。 | `tasks_tab.dart` L103-121；`voice_input_screen.dart` L153-162 | 5s→3s、样式/动效、成功反馈需改 |
| F8 | 记事本入口卡 `NotebookHubCard` 用 `Column(crossAxisAlignment: CrossAxisAlignment.start)`，图标/标题/计数**靠左**。 | `lib/modules/notebook/widgets/notebook_hub_card.dart` L41 | 居中需改为 `center` |
| F9 | 滑动删除：`TaskCard` 的 `Dismissible.onDismissed` 直接调 `onDelete`（即先删后撤销），**无二次确认**。 | `lib/widgets/task_card.dart` L80-92 | 需加 `confirmDismiss` 二次确认 |

> UI 可设项 ↔ 解析能力对齐矩阵（来自 `AddTaskScreen`）：

| UI 可设参数 | Hive 字段 | 云端 prompt 现状 | 本地 fallback 现状 | 缺口 |
|---|---|---|---|---|
| 任务内容 title | title@1 | ✓ | ✓ | 无（需强化去参，见块二） |
| 指定时间 datetime | scheduledTime@2 | ✓ | ✓ | 无 |
| 倒计时 remind | countdownSeconds@16 | 内联有 / YAML 无 | ✓ | YAML 补字段 |
| 重复 repeat | repeat@4 + customWeekdays@5 | 仅显式关键词 | 仅显式关键词 | 语义推断强化 |
| 所需资源 resource | resource@11 | ✓ | **缺失** | 本地补抽取 |
| 任务时长 duration | durationMinutes@14 | ✓(默认60) | **缺失(硬编码60)** | 本地补抽取 |
| 响铃时长 ring | ringSeconds@15 | **缺失** | **缺失** | prompt + ScheduledTask + toTask 补 |

---

## 4. 需求池

> 每条标注所属块：【一】参数提取与生效 /【二】标题智能提炼 /【三】UI 与交互强化。

### 块一 · 任务参数提取与生效

**P0-1.1 云端 prompt 与 UI 可设项参数集对齐（单一真源）**【一】
- 云端排期统一改用 `PromptLoader.byId('tasks_voice')`（YAML）作为唯一 prompt 来源，**删除 `_callModel` 内联 prompt**（消除 F2 两源不一致）；更新 YAML `output_format` 为下方完整参数 schema。
- 要求模型：未提及的参数填 `null`/默认，**不得臆造**（如未说资源则 `resource: null`）。
- 【验收】云端 prompt schema 覆盖 `AddTaskScreen` 全部可设项（title / 指定时间 / 倒计时 / 重复 / 资源 / 时长 / 响铃）；`aliyun_schedule_service` 不再内联硬编码 prompt。

**P0-1.2 重复判定：语义推断（非仅显式表述）**【一】
- 云端 + 本地均须：用户未明说"重复"也可能隐含重复——含**习惯性/周期性表述**即判重复：
  - 「每天早上 8 点 / 每晚睡前 / 每天起床后…」→ `repeat=daily`，`datetime`=对应时刻（今天若已过则次日）。
  - 「每周一开会 / 周一三五健身」→ `repeat=custom` + `weekdays`（或 `weekly` 按设定日）。
  - 「工作日…」→ `repeat=weekdays`。
  - 仅单次动作（「明早 9 点吃药」「10 秒后倒垃圾」）→ `repeat=none`。
- 【验收】「每天早上 8 点执行」→ `repeat=daily` 且 `datetime≈今天/次日 08:00`；「每周一开会」→ `custom`+`[1]`；「明早 9 点吃药」→ `none` 且单次。

**P0-1.3 所有参数实际应用（云端 → Task）**【一】
- `ScheduledTask` 新增 `int? ringSeconds`；`parseJson` 读取 `ring_seconds`；`toTask` 写入 `ringSeconds`；确认 `duration_minutes/resource/repeat/weekdays/remind_*` 已透传。
- `voice_input_screen._PreviewTile` 预览中展示已提取的**资源/时长/响铃**（P1：新增轻量徽标，与现有时间/重复/倒计时徽标并列）。
- 【验收】云端返回含 `resource/duration/ring` 的任务 → 创建的 `Task` 对应字段非空且正确；预览可见。

**P0-1.4 本地 NlpParser 回退补齐（资源 / 时长 / 重复语义 / 标题不含参数）**【一】
- `ParsedTask` 新增 `String? resource`、`int? durationMinutes`；`NlpParser` 增加：
  - **资源抽取**：识别「在/用/占用 + [会议室A/车/张经理…]」等模式 → `resource`（best-effort 启发式）。
  - **时长抽取**：识别「持续/历时/做 X 用/约 X（分钟|小时）」并与**倒计时**（`X 分钟后`）区分 → `durationMinutes`；无则为 `null`（上游默认 60）。
  - **重复语义**：在现有显式关键词基础上，补「每天 + 时刻」「每晚/每早」等习惯性表述（与云端契约一致）。
  - **标题**：`_extractCorePurpose` 已剥离参数，补充保证不残留「每天/每/周/点/秒/分/资源名」等；精炼为空则回退 `_cleanTitle`。
- `_fallback` 透传 `resource` 与 `durationMinutes`（当前丢弃 resource、duration 硬编码 60）。
- 【验收】本地路径同样产出 resource/duration/重复语义/无参标题，与云端行为一致（≥8 条 fixture，覆盖资源/时长/每天/每周/无参标题）。

**P0-1.5 任务模型字段与 Hive 兼容策略**【一】
- **关键确认**：所需字段**已存在**（见 F1），本增量**无需新增 Hive 字段**；`lib/models/task.dart` 可零改动。工作是把字段填实。
- **Hive 兼容策略（若后续确需新字段）**：尾部追加 `@HiveField(17)` 起；`TaskAdapter.read` 对所有字段 `?? 默认`（现状已实践，老数据缺字段读回 null/默认不崩溃）；`write` 的 `writeByte(N)` 随字段数递增。升级不破坏旧数据。
- 【验收】升级后旧任务数据正常加载、不崩溃；无新字段则 `task.dart` 不改。

### 块二 · 提醒标题智能提炼

**P0-2.1 标题语义拆解提炼核心目的（云端）**【二】
- prompt 增加强约束：`title` = 对输入做**语义拆解后的核心目标/动作短语**，**严禁**包含触发时间、提醒/倒计时时长、重复表述、资源名、时长数字等任何参数文本。
  - 例：「设置提醒时间为 10 秒，去健身房练腿」→「去健身房练腿」；「每天早上 8 点背单词」→「背单词」。
- 【验收】≥5 条用例 `title` 均不含参数且与核心目标一致。

**P0-2.2 标题提炼不含参数（本地，与云端契约对齐）**【二】
- `_extractCorePurpose` 已剥离参数（F6）；补充边界保证不残留参数文本，且与云端输出**语义等价**（核心名词相同）。
- 【验收】与云端输出语义等价；`title` 不含任何时间/资源/重复/时长文本。

### 块三 · UI 与交互强化

**P0-3.1 操作反馈卡片：样式 + 3 秒消失动效**【三】
- 持续时间 **5s → 3s**：`tasks_tab._showUndo` 的 `SnackBar.duration` 与兜底定时器均改为 3s。
- 新增可复用反馈组件 `lib/widgets/task_feedback_card.dart`（`TaskFeedbackCard`）：圆角卡片（radiusLg）、语义色（成功=ok/accent、删除/撤销=danger/warn）、左侧图标 + 文案 + 可选「撤销」action；**进入淡入/上滑，3 秒后滑出 + 淡出动效消失**（用 Overlay + AnimatedOpacity/SlideTransition 控制，而非默认 SnackBar 固定动画）。
- **删除（撤销槽）**：沿用现有「先删 + 撤销」机制，套用新卡片，3 秒内有「撤销」可点。
- **成功反馈（语音创建）**：`voice_input_screen._confirm` 当前在 `showSnackBar` 后立即 `pop` 导致不可见——改为经 `Navigator.pop(result)` 把"已添加 N 项"回传 `tasks_tab`，由 `tasks_tab` 统一用 `TaskFeedbackCard` 展示（成功/删除/撤销三态**共用同一组件**）。
- 【验收】三态反馈均为同款卡片、3 秒消失、带滑出淡出动效；删除后 3 秒内有「撤销」可点；语音创建成功后反馈在任务列表页可见。

**P0-3.2 记事本内容与功能图标居中**【三】
- `NotebookHubCard` 的 `Column(crossAxisAlignment: CrossAxisAlignment.start)` → `CrossAxisAlignment.center`（图标容器、标题、计数整体水平居中）；其余视觉不变。
- 【验收】六大入口卡（图标 + 标题 + 条数）均水平居中，不再靠左。

**P0-3.3 滑动删除二次确认**【三】
- `TaskCard` 的 `Dismissible` 新增 `confirmDismiss` 回调（父级提供），返回 `Future<bool>`：弹出**确认卡片/弹窗**（复用 AppTheme 的 `AlertDialog` 风格，文案"确定删除该任务？删除后可在下方提示中撤销" + 取消/删除），确认才继续 `onDismissed` → `_deleteWithUndo`；取消则卡片回弹。
- `tasks_tab` 提供 `confirmDismiss` 实现（`showDialog` 返回 bool）；保持 `selectionMode` 时禁用滑动（现状 `direction: none`）。
- 【验收】左滑任务先弹确认，确认后才删除并出现撤销反馈；取消则不动。

**P1-3.4 语音预览强化（资源/时长/响铃）**【一/三】
- 同 P0-1.3 的预览徽标（资源/时长/响铃），复用 `NotebookChip` / `AppTheme` 语义色，与现有时间/重复/倒计时徽标并列，便于用户核对。
- 【验收】预览页对含资源/时长/响铃的任务显示对应徽标。

**P2-3.5 解析一致性回归测试**
- 为云端 `parseJson` 与本地 `NlpParser` 增加参数化双路径一致性用例（资源/时长/每天/每周/无参标题）。

---

## 5. UI 设计要点（草图级，引用可复用组件）

> 风格统一：发丝边框 + 扩散阴影卡片、`AppTheme` 圆角（10/14/20）与语义色、完整空/错/加载态。

### 5.1 操作反馈卡片（新增 `TaskFeedbackCard`，替换默认 SnackBar）
```
        ┌──────────────────────────────────┐  ← 圆角卡片 radiusLg，floating 居中偏下
        │ ✓  已添加 3 个任务        (3s 后滑出淡出) │  成功：ok 色图标
        └──────────────────────────────────┘
        ┌──────────────────────────────────┐
        │ 🗑  已删除            [撤销]      │  删除：warn/danger 色 + 撤销 action
        └──────────────────────────────────┘
```
- 进入：淡入 + 上滑 8px；消失：下滑 + 淡出（约 250ms）。3 秒后自动触发。

### 5.2 滑动删除二次确认弹窗（复用 AppTheme AlertDialog）
```
        ┌──────────────────────────────────┐
        │        确定删除该任务？            │
        │   删除后可在下方提示中撤销。        │
        │                            [取消] [删除] │  ← 删除=danger 色
        └──────────────────────────────────┘
```
- `confirmDismiss` 返回 true 才真正删除；false 卡片回弹。

### 5.3 记事本首页入口卡（居中，改动 `NotebookHubCard`）
```
   ┌────────────┐   ┌────────────┐
   │   🛍️      │   │   💰      │     ← 图标容器居中
   │  购物清单   │   │  收支账本   │     ← 标题居中
   │   3 条     │   │   12 条    │     ← 计数居中
   └────────────┘   └────────────┘
   （原：全部靠左 → 改为整体 CrossAxisAlignment.center）
```

### 5.4 语音预览（P1-3.4，可选增强）
```
   [✓] 开会         📍会议室A  ⏱60分  ⏰15:00
   [✓] 背单词       🔁每天     ⏰08:00
```
- 资源/时长/响铃以 `NotebookChip` 轻量徽标呈现，与现有时间/重复/倒计时徽标并列。

---

## 6. 待确认问题（真实歧义，需产品/技术拍板）

1. **Q1 "任务时长"语义界定**：UI 的 `durationMinutes` 注释明确是"冲突按时间段判断、默认 60"。但口语「吃药 30 分钟」可能指持续/占用时长，而非提醒。建议：`durationMinutes` = 该任务**占用时段**（默认 60），与倒计时（`remind_in_seconds`）**分离**；若口语同时含"X 分钟后提醒 + Y 小时时长"则分别填。需确认本地解析的"时长"抽取口径。
2. **Q2 "所需资源"多值处理**：模型为单字符串 `resource`（用于资源冲突检测）。语音抽到多个资源（"用车并约张经理"）时：建议保持**单资源**（取首个/主资源）以匹配现有冲突模型；或改为 `List<String>`（需改模型 + 冲突检测）。需确认。
3. **Q3 滑动删除"确认卡片"形态**：用原生 `AlertDialog`（与现有批量删除确认风格一致）还是自定义底部/居中卡片？建议复用 AppTheme `AlertDialog` 保持一致。
4. **Q4 成功反馈承载位置**：语音页 `pop` 后 SnackBar 不可见，本 PRD 建议经 `Navigator.pop(result)` 回传 `tasks_tab` 统一展示（三态共用 `TaskFeedbackCard`）。需确认路由回传方式是否可接受。
5. **Q5 重复语义推断边界**：「我习惯每天喝水」这类纯习惯描述是否判为重复任务？建议仅对"含明确动作 + 时间的习惯性表述"判重复，纯习惯描述不生成任务。需确认。

---

## 7. 影响面与文件改动索引（增量）

| 文件 | 关联需求 | 改动性质 |
|------|----------|----------|
| `assets/prompts/tasks_voice.yaml` | P0-1.1, P0-1.2, P0-2.1 | 改：完整参数 schema + 语义重复 + 标题去参规则 |
| `lib/services/aliyun_schedule_service.dart` | P0-1.1, P0-1.3 | 改：删内联 prompt 改用 YAML；`ScheduledTask`+`ringSeconds`；`parseJson`/`toTask`/`_fallback` 透传 resource/duration/ring |
| `lib/services/nlp_parser.dart` | P0-1.4, P0-2.2 | 改：`ParsedTask`+`resource/durationMinutes`；资源/时长抽取；重复语义；标题去参边界 |
| `lib/models/task.dart` + `TaskAdapter` | P0-1.5 | 声明**无需改动**（若新字段按 `@HiveField(17)`+ 追加） |
| `lib/modules/tasks/voice_input_screen.dart` | P0-1.3(P1 预览), P0-3.1 | 改：预览资源/时长/响铃(P1)；成功反馈经 `pop(result)` 回传 |
| `lib/modules/tasks/tasks_tab.dart` | P0-3.1, P0-3.3 | 改：`_showUndo` 5s→3s + `TaskFeedbackCard`；接收成功反馈；提供 `confirmDismiss` |
| `lib/widgets/task_card.dart` | P0-3.3 | 改：`Dismissible` 新增 `confirmDismiss` 回调 |
| `lib/widgets/task_feedback_card.dart`（**新增**） | P0-3.1 | 新增：可复用反馈卡片（3s 滑出淡出） |
| `lib/modules/notebook/widgets/notebook_hub_card.dart` | P0-3.2 | 改：`CrossAxisAlignment.start`→`center` |

**测试文件（test/，package `daily_planner`）**

| 测试文件 | 关联需求 |
|----------|----------|
| `test/aliyun_schedule_test.dart` | P0-1.3：`ring_seconds`/`resource`/`duration`/语义重复解析 + `toTask` 映射 |
| `test/nlp_parser_test.dart` | P0-1.4, P0-2.2：资源/时长/每天/每周/无参标题 fixture |
| `test/tasks_tab_undo_snackbar_test.dart` | P0-3.1：5s→3s + 新反馈卡片 |
| `test/snackbar_auto_dismiss_test.dart` | P0-3.1：按需调整为 3s 期望 |
| `test/notebook_hub_card_test.dart` | P0-3.2：增加居中（`center`）断言 |
| `test/task_card_dismiss_confirm_test.dart`（**新增**） | P0-3.3：滑动二次确认（confirm→删 / cancel→回弹） |
| `test/task_feedback_card_test.dart`（**新增**） | P0-3.1：反馈卡片渲染 + 3s 消失动效 |

---

*注：本 PRD 为「简单 PRD 级别」，聚焦增量变更与可验收标准，供架构师拆分任务使用；完整竞品/象限分析不在本增量范围。关键澄清：任务模型字段（repeat/resource/durationMinutes/ringSeconds/countdownSeconds）均已存在，本增量无需新增 Hive 字段，重点是 prompt + 本地解析 + 透传把字段填实。*

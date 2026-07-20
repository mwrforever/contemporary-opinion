# 增量架构设计 · 每日规划助手「参数提取与生效 / 标题提炼 / UI 交互强化」

- **项目路径**：`D:\code\project\contemporary-opinion`（Flutter 3.44.6 + Dart）
- **增量日期**：2026-07-19
- **设计师**：高见远（software-architect）
- **基线**：已确认增量 PRD（许清楚，已读代码）+ 代码核查（见 §1）

> 类图见 `docs/class-diagram-task-enhance_2026-07-19.mermaid`，时序图见 `docs/sequence-diagram-task-enhance_2026-07-19.mermaid`。

---

## 1. 背景与现状边界（代码核查结论）

| 编号 | 现状事实（已读代码确认） | 对本增量的含义 |
|------|--------------------------|----------------|
| F1 | `lib/models/task.dart`：`Task` 字段齐全——`repeat@4`、`customWeekdays@5`、`resource@11`、`durationMinutes@14`、`ringSeconds@15`、`countdownSeconds@16`；`TaskAdapter` 写 17 个字段（索引 0–16）。 | **本增量 `task.dart` 零改动**，重点是填实已有字段。 |
| F2 | `lib/services/aliyun_schedule_service.dart`：`_callModel` 内联 system prompt；`assets/prompts/tasks_voice.yaml` 已被 `PromptLoader` 加载，但云端路径**未消费**它（`voice_input_screen._buildSchedule` 仅用它判空）。 | P0-1.1：云端统一改用 `PromptLoader.byId('tasks_voice')`。 |
| F4 | `ScheduledTask` 无 `ringSeconds`；`toTask` 未写 `ringSeconds`；`_fallback` 丢弃 `resource` 且 `durationMinutes` 硬编码 60。 | P0-1.3 / P0-1.4 需在 `ScheduledTask` 加字段并透传。 |
| F5 | `lib/services/nlp_parser.dart`：不抽 `resource`、不抽 `durationMinutes`；`ParsedTask` 无这两字段；重复仅显式关键词；`_extractCorePurpose` 已有去参基线。 | P0-1.4 补齐本地回退。 |
| F7 | `tasks_tab._showUndo` 用默认 SnackBar、duration 5s + 兜底定时器 5s；`voice_input_screen._confirm` 弹 SnackBar 后立即 `pop`（不可见）。 | P0-3.1 改 3s 动效卡片 + 成功改 `pop(result)` 回传。 |
| F8 | `NotebookHubCard` 用 `CrossAxisAlignment.start`。 | P0-3.2 → `center`。 |
| F9 | `TaskCard.Dismissible.onDismissed` 直接 `onDelete`（先删后撤销），无二次确认。 | P0-3.3 加 `confirmDismiss` 回调。 |
| F0 | `PromptLoader.loadAll()` 在 `lib/main.dart:53` 以 `await` 调用（应用启动时完成）。 | D1 加载时机安全：YAML 在语音录入前已缓存，`byId` 可同步读取。 |
| F0b | `SettingsService.defaultRingSeconds = 5`；`reminder_service.dart:239` 用 `task.ringSeconds ?? settings?.ringSecondsDefault ?? 5`。 | `ringSeconds=null` 时回退全局默认 5s，无需额外处理。 |

---

## 2. 实现方案 + 框架选型

**沿用现有栈，零新依赖**：
- **UI**：Flutter（Material + `AppTheme` 设计令牌）。
- **存储**：Hive（手写 `TaskAdapter`，`task.dart` 不变）。
- **状态**：Provider（`TaskStore` 经 `context.read` 注入）。
- **云端排期**：自建 `AliyunScheduleService`（通义千问 / DashScope OpenAI 兼容接口，关闭思考模式，JSON 输出）。
- **本地回退**：自建 `NlpParser`（纯正则启发式）。
- **提示词**：`PromptLoader` + `assets/prompts/*.yaml`（只读资源，单一真源）。
- **反馈组件**：`Overlay` + `AnimatedOpacity`/`SlideTransition` 原生实现（**不引图表/动画库**）。

**核心思路**：
1. **单一真源**：云端 prompt 与 UI 可设项对齐——全部由 `tasks_voice.yaml` 定义，`_callModel` 删除内联 prompt。
2. **参数填实**：`ScheduledTask` / `ParsedTask` 补齐 `ringSeconds`/`resource`/`durationMinutes`，云端 `parseJson`→`toTask` 与本地 `_fallback` 全链路透传。
3. **标题去参**：云端（YAML 强约束）+ 本地（`_extractCorePurpose` 边界）双轨保证 `title` 不含参数文本。
4. **反馈统一**：新增 `TaskFeedbackCard`（success/delete/undo 三态共用），`tasks_tab` 统一承载；成功反馈经 `Navigator.pop(result)` 回传。

---

## 3. 设计裁决（D1–D4）

### D1 · P0-1.1 是否真删内联 prompt 改 YAML？
**裁决：是，统一为 YAML 单一真源。** 删除 `_callModel` 内联 system 字符串，改用 `PromptLoader.byId('tasks_voice')!.prompt`。

- **YAML 当前 schema 不覆盖全部参数**（风险已核实）：现 `output_format` 仅有 `title/datetime/duration_minutes/resource/repeat/weekdays/note`，**缺 `remind_in_seconds`(倒计时) 与 `ring_seconds`(响铃)**，且 `title` 无"禁止含参数"强约束。→ P0-1.1 必须先把 YAML `output_format` 扩成完整 schema（见 §8 映射表 + 下方"YAML 必补字段"）。
- **加载时机安全**：`PromptLoader.loadAll()` 在 `main.dart:53` 启动期 `await` 完成，语音录入时缓存已就绪，`byId` 同步可用。
- **回退一致性（改进）**：现 `voice_input_screen._buildSchedule` 在 `prompt==null` 时走 `error` state。改为：`_callModel` 内 `final p = PromptLoader.byId('tasks_voice')?.prompt; if (p == null) throw StateError(...)` → `schedule()` 的 `catch` 落到 `_fallback()`（本地 NlpParser），与"云端异常即回退"保持一致，比当前"报错卡死"更稳健。**不保留任何内联兜底 prompt 常量。**
- **YAML 必补字段与语义重复规则**：
  - 字段：`title`、`datetime`(或 `remind_in_seconds`/`remind_in_minutes`)、`duration_minutes`、`resource`、`repeat`(`none|daily|weekdays|weekly|custom`)、`weekdays`、`ring_seconds`、`note`。
  - 重复语义规则（写进 YAML `<task>`/`<critical_reminders>`）：
    - 「每天早上8点 / 每晚睡前」→ `daily` + 对应 `datetime` 时刻；
    - 「每周一开会 / 周一三五」→ `custom` + `weekdays:[1]` / `[1,3,5]`；
    - 「工作日」→ `weekdays`；「每周(无具体星期)」→ `weekly`；
    - 单次 → `none`；**无明确重复指示默认 `none`**。
  - `title` 强约束：`title` = 语义拆解后的核心目的/动作短语，**严禁含触发时间、提醒时长、重复、资源等参数文本**（例：「设置提醒时间为10秒，去健身房练腿」→「去健身房练腿」）。
  - 未提及参数填 `null` 或安全默认（duration=60、repeat=none、weekdays=[]），**不得臆造**。

### D2 · `resource` 多值处理
**裁决：保持单资源 `String?`（与现有冲突模型一致）。** 抽到多个资源时取**首个/主资源**，不改为 `List<String>`（避免动 `Task` 模型 + Hive + `ConflictDetector`）。`ScheduledTask.resource` / `ParsedTask.resource` / `Task.resource` 均为 `String?`。云端由模型自由产出单字符串；本地 `NlpParser._extractResource` 取首个人名/地点/会议室类 token（启发式，见 §4）。

### D3 · `durationMinutes` 语义与本地抽取口径
**裁决：`durationMinutes` = 占用时段（默认 60 分钟），与 `countdownSeconds`（相对触发倒计时）严格分离。**
- 用途：冲突检测按"时段"重叠判定（见 `Task.nextOccurrence`）。
- **本地抽取口径**（避免与倒计时混淆）：
  - **时长（duration）**：仅在**显式时长提示词**后出现——`持续 / 历时 / 花费 / 占用 / 长达 + N (分钟|小时|分|时)` → 折算分钟（小时×60）。抽取后从文本移除（保持标题干净）。**无提示词的裸 "N分钟" 本地不推断**（保守，避免误吞），由云端 `duration_minutes` 兜底。
  - **倒计时（countdown）**：保留现有逻辑——`X分钟后/小时后/天后`（相对时间正则，含"后"后缀）或 `X秒后` / `提醒时间(为)X秒|分|时`（`_parseSeconds`）→ `countdownSeconds`。
  - **不冲突保证**：时长要求提示词、倒计时要求"后"或"提醒时间"，二者模式互斥；仍规定**先抽时长再抽倒计时**，杜绝 "持续30分钟" 被倒计时正则误吃。
  - 本地未抽到 → `ParsedTask.durationMinutes = null` → `_fallback` 填默认 60（与 `ScheduledTask` 默认值一致）。

### D4 · 成功反馈承载方式
**裁决：经 `Navigator.pop(result)` 回传 `tasks_tab` 统一展示。**
- `VoiceInputScreen._confirm` 移除屏内 SnackBar，改为 `Navigator.of(context).pop({'added': n, 'conflict': k})`。
- `tasks_tab._goVoice` 改为 `final r = await Navigator.of(context).push(...)`；`r != null` 时用 `TaskFeedbackCard`（success 态）展示。
- 删除（delete+undo）、撤销（undo）、成功（success）三态**共用同一 `TaskFeedbackCard`**，由 `tasks_tab` 统一承载（见 §4 / §5-SD1）。

---

## 4. 文件列表（改动 + 新增，含 test/）

### 改动文件
| 文件 | 改动摘要 |
|------|----------|
| `assets/prompts/tasks_voice.yaml` | `output_format` 扩为完整参数 schema（含 `remind_in_seconds`/`ring_seconds`）；新增 `title` 禁参强约束与重复语义规则（D1）。 |
| `lib/services/aliyun_schedule_service.dart` | `ScheduledTask` 加 `int? ringSeconds` + 构造/`toTask` 写入；`_callModel` 改用 `PromptLoader.byId('tasks_voice').prompt`（删内联）；`parseJson` 读 `ring_seconds`；`_fallback` 透传 `resource` / `durationMinutes`。 |
| `lib/services/nlp_parser.dart` | `ParsedTask` 加 `String? resource` / `int? durationMinutes`；`NlpParser` 加 `_extractResource` / `_extractDurationMinutes`；重复语义补「睡前/每晚→daily+时刻」；`_extractCorePurpose` 强化去参边界；`_parseClause` 回填新字段。 |
| `lib/modules/tasks/voice_input_screen.dart` | `_PreviewTile` 展示 `durationMinutes` + `ringSeconds`（P1-3.4）；`_confirm` 改 `Navigator.pop(result)`（移除屏内 SnackBar，D4）。 |
| `lib/modules/tasks/tasks_tab.dart` | `_showUndo` → `TaskFeedbackCard`(delete+undo, 3s)；`_goVoice` 改为 `await` 回传结果并弹 success 卡；新增 `_confirmDelete`（AlertDialog）作 `confirmDismiss` 实现（P0-3.3）。 |
| `lib/widgets/task_card.dart` | `Dismissible` 加 `confirmDismiss: Future<bool> Function()?` 回调；`onDismissed` 保持 `onDelete`（P0-3.3）。 |
| `lib/modules/tasks/task_list.dart` | 加 `confirmDismiss` 透传属性并传给 `TaskCard`。 |
| `lib/modules/notebook/widgets/notebook_hub_card.dart` | `CrossAxisAlignment.start` → `center`（P0-3.2）。 |
| `lib/models/task.dart` | **零改动**（P0-1.5；字段已存在，Hive 最大索引 16 / 写 17 不变）。 |
| `test/aliyun_schedule_test.dart` | 扩用例：断言 `ring_seconds`→`ringSeconds`、`title` 无参、重复语义。 |
| `test/nlp_parser_test.dart` | 扩用例：资源/时长/重复语义/标题去参。 |
| `test/tasks_tab_undo_snackbar_test.dart` | 改为校验 `TaskFeedbackCard` 删除+撤销（3s）。 |
| `test/notebook_hub_card_test.dart` | 校验居中对齐。 |
| `test/task_adapter_test.dart` | 校验 `Task` Hive 往返不变、`ringSeconds`@15 保留、无新增 `@HiveField`。 |

### 新增文件
| 文件 | 说明 |
|------|------|
| `lib/widgets/task_feedback_card.dart` | 可复用反馈组件：`FeedbackType{success,delete,undo}` + `show()`（`Overlay` + `AnimatedOpacity`/`SlideTransition`，3s 自动消失）。 |
| `test/task_feedback_card_test.dart` | 组件测试：三态渲染、3s 自动移除、撤销 `onAction` 触发。 |
| `test/task_card_confirm_test.dart` | `confirmDismiss` 测试：取消→回弹不删、确认→`onDismissed` 触发。 |

---

## 5. 数据结构与接口（类图）

> 完整 mermaid 类图见 `docs/class-diagram-task-enhance_2026-07-19.mermaid`。要点：

### 5.1 `Task`（不变，`lib/models/task.dart`）
已有全部字段；本次仅消费 `ringSeconds@15`、`resource@11`、`durationMinutes@14`、`repeat@4`、`customWeekdays@5`。`TaskAdapter` 读/写索引 0–16，全部 `?? ` 默认值，兼容旧数据。

### 5.2 `ScheduledTask`（改，`aliyun_schedule_service.dart`）
```
class ScheduledTask {
  final String title;
  final DateTime? scheduledTime;
  final int durationMinutes;          // 默认 60
  final String? resource;             // 新增透传
  final RepeatType repeat;
  final List<int> customWeekdays;
  final String? note;
  final int? countdownSeconds;
  final int? ringSeconds;             // ★ 新增
  Task toTask({required String id, required int notificationId, required DateTime createdAt}) =>
      Task(..., ringSeconds: ringSeconds, resource: resource, durationMinutes: durationMinutes, ...);
}
```

### 5.3 `ParsedTask`（改，`nlp_parser.dart`）
```
class ParsedTask {
  final String title;
  final DateTime? scheduledTime;
  final RepeatType repeat;
  final List<int> customWeekdays;
  final int? countdownMinutes;
  final int? countdownSeconds;
  final String? resource;             // ★ 新增
  final int? durationMinutes;         // ★ 新增
}
```

### 5.4 `TaskFeedbackCard`（新增，`lib/widgets/task_feedback_card.dart`）
```
enum FeedbackType { success, delete, undo }
class TaskFeedbackCard {
  static void show(BuildContext context, {
    required FeedbackType type,
    required String message,
    String? actionLabel,        // delete 态用："撤销"
    VoidCallback? onAction,     // 撤销回调
    Duration duration = const Duration(seconds: 3),
  });
  // 内部：OverlayEntry + AnimatedOpacity + SlideTransition；
  // 进入 淡入+上滑(~280ms) → 停留 duration(3s) → 退出 下滑+淡出(~280ms) → remove。
}
```
三态语义色：`success`→`AppTheme.accent`(teal)+check；`delete`→`AppTheme.danger`+删除图标（可选撤销）；`undo`→`AppTheme.accent`+undo 图标。

### 5.5 `TaskCard` `confirmDismiss` 契约（改，`task_card.dart`）
```
class TaskCard {
  final Task task;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;                  // 保持；onDismissed 仍 = onDelete
  final Future<bool> Function()? confirmDismiss;// ★ 新增；父级提供
  final bool selectionMode;
  ...
  // Dismissible:
  //   confirmDismiss: (_) async => confirmDismiss == null ? true : await confirmDismiss!();
  //   onDismissed: (_) => onDelete();   // 仅当 confirmDismiss 返回 true 才触发
}
```
`TaskList` 新增同名透传属性 `Future<bool> Function(Task)? confirmDismiss`，在 `_card` 中传给 `TaskCard(confirmDismiss: () => confirmDismiss?.call(task))`。`tasks_tab` 提供 `_confirmDelete(Task)`：`showDialog<bool>`（AppTheme AlertDialog，文案"确定删除该任务？删除后可在下方提示中撤销"，取消/删除）→ 返回 `bool`；`selectionMode` 下 `Dismissible` 方向为 `none`，`confirmDismiss` 不参与。

---

## 6. 程序调用流程（时序图）

> 完整 mermaid 时序图见 `docs/sequence-diagram-task-enhance_2026-07-19.mermaid`，含三条：
> - **SD1** 语音录入 → 云端解析 → 参数填实 → 成功经 `pop(result)` 回传 `tasks_tab` 弹 `TaskFeedbackCard(success)`。
> - **SD2** 云端失败 → 本地 `NlpParser` 回退（抽 resource/durationMinutes/重复语义）→ `_fallback` 透传。
> - **SD3** 左滑 → `confirmDismiss` → AlertDialog 确认/取消 → 确认则 `onDismissed`→删除→`TaskFeedbackCard(delete+撤销)`；取消则 `Dismissible` 自动回弹。

---

## 7. 任务列表（T1–T8，有序 + 依赖 + 改动点 + 验收点）

> 覆盖 P0-1.1~1.5、P0-2.1~2.2、P0-3.1~3.3 及 P1-3.4、P2-3.5。
> 任务内已含依赖；T6 与 T5 均改 `tasks_tab`，故 T6 排在 T5 之后由工程师顺次落地。

### T1 · 云端 prompt 单一真源 + 参数 schema 落地
- **对应**：P0-1.1、P0-1.3(ring/parse)、P0-2.1、D1
- **改动文件**：`assets/prompts/tasks_voice.yaml`、`lib/services/aliyun_schedule_service.dart`、`test/aliyun_schedule_test.dart`
- **关键改动点**：
  1. YAML `output_format` 扩为完整 schema：`title`(禁参强约束)、`datetime` 或 `remind_in_seconds`/`remind_in_minutes`、`duration_minutes`、`resource`、`repeat`(none|daily|weekdays|weekly|custom)、`weekdays`、`ring_seconds`、`note`；追加重复语义规则（见 §3-D1）。
  2. `_callModel` 删除内联 prompt，改 `final p = PromptLoader.byId('tasks_voice')?.prompt; if (p == null) throw StateError('tasks_voice prompt missing');` 以 `p` 为 system。
  3. `ScheduledTask` 加 `final int? ringSeconds;` + 构造参 + `toTask` 写入 `ringSeconds: ringSeconds`。
  4. `parseJson` 读 `m['ring_seconds']`：`rawRing == null || rawRing == 0 ? null : _asInt(rawRing, 0)`。
- **验收点**：给定含"响铃/倒计时/资源/重复"的转写，`schedule()` 返回的 `ScheduledTask.ringSeconds`/`resource`/`durationMinutes`/`repeat` 正确；`title` 不含参数文本；`prompt==null` 时走本地 `_fallback` 而非卡死 error。

### T2 · 本地 NLP 回退补齐（资源/时长/重复语义/标题）
- **对应**：P0-1.4、P0-1.2(本地)、P0-2.2
- **依赖**：T1（`ScheduledTask.ringSeconds` 已存在；`_fallback` 使用 `ParsedTask` 新字段）
- **改动文件**：`lib/services/nlp_parser.dart`、`lib/services/aliyun_schedule_service.dart`(仅 `_fallback`)、`test/nlp_parser_test.dart`
- **关键改动点**：
  1. `ParsedTask` 加 `String? resource`、`int? durationMinutes` + 构造。
  2. `NlpParser` 新增 `_extractResource`（`在|用|占用|使用|借|租` + 资源 token，取首个）与 `_extractDurationMinutes`（`持续|历时|花费|占用|长达` + N 分钟/小时，先抽后清文本）。
  3. 重复语义补：「睡前/睡觉前」→ 时刻 23:00 且 `daily`；「每晚/每天早上」→ `daily`；其余沿用现有（工作日→weekdays、每周X/周一三五→custom）。
  4. `_extractCorePurpose` 强化去参边界（确保"设置提醒时间为10秒，去健身房练腿"→"去健身房练腿"）。
  5. `_parseClause` 回填 `resource`/`durationMinutes`；`_fallback` 改为 `resource: p.resource`、`durationMinutes: p.durationMinutes ?? 60`（保留 `countdownSeconds`）。
- **验收点**："占用会议室A开会1小时"→`resource='会议室A'`、`durationMinutes=60`、weekdays 正确；"每晚睡前跑步"→`repeat=daily`+时刻~23:00；本地回退任务 `resource`/`durationMinutes` 透传（ringSeconds 为 null 走全局默认）。

### T3 · 语音预览平铺补齐资源/时长/响铃
- **对应**：P1-3.4
- **依赖**：T1（`Task.ringSeconds` 经 `ScheduledTask→toTask` 已填实）
- **改动文件**：`lib/modules/tasks/voice_input_screen.dart`（仅 `_PreviewTile`）
- **关键改动点**：`_PreviewTile` 在现有「资源 / 倒计时秒」基础上新增展示 `task.durationMinutes`（如「60分钟」）与 `task.ringSeconds`（如「响铃10秒」）；位置与现有 meta 行一致（图标+胶囊）。
- **验收点**：预览卡片对含时长/响铃的候选正确展示 `durationMinutes` 与 `ringSeconds`（不展示则条件隐藏）；布局不与现有 meta 重叠。

### T4 · TaskFeedbackCard 复用组件
- **对应**：P0-3.1（组件层）
- **依赖**：无
- **改动文件**：`lib/widgets/task_feedback_card.dart`(新)、`test/task_feedback_card_test.dart`(新)
- **关键改动点**：实现 `FeedbackType{success,delete,undo}` + `show()`：`OverlayEntry` + `AnimatedOpacity`/`SlideTransition`，进入淡入上滑、停留 `duration`(默认 3s)、退出下滑淡出后 `remove`；三态语义色（见 §5.4）；`delete` 态带可选 `actionLabel`/`onAction`（撤销）。
- **验收点**：三态均能被 `show()` 渲染；约 3s 后自动从 Overlay 移除；`delete` 态点击撤销触发 `onAction`；动画期间不阻塞页面交互。

### T5 · 操作反馈统一 + 3s + 成功经路由回传
- **对应**：P0-3.1（集成层）
- **依赖**：T4
- **改动文件**：`lib/modules/tasks/tasks_tab.dart`、`lib/modules/tasks/voice_input_screen.dart`、`test/tasks_tab_undo_snackbar_test.dart`
- **关键改动点**：
  1. `tasks_tab._showUndo` 改写：移除 SnackBar 与 5s 兜底定时器，改调 `TaskFeedbackCard.show(type: delete, message, actionLabel:'撤销', onAction: undo, duration: 3s)`。
  2. `voice_input_screen._confirm` 移除屏内 SnackBar，改 `Navigator.of(context).pop({'added': chosen.length, 'conflict': conflictCount})`。
  3. `tasks_tab._goVoice` 改 `final r = await Navigator.of(context).push(...)`；`r is Map && r['added'] != null` 时 `TaskFeedbackCard.show(type: success, message:'已添加 ${r['added']} 个任务' + 冲突提示)`。
- **验收点**：删除提示 3s 自动消失且可撤销；语音确认添加后返回 `tasks_tab` 弹 success 卡（此前屏内 SnackBar 不可见问题消除）；`_goVoice` 返回路径无残留 SnackBar。

### T6 · 滑动删除二次确认
- **对应**：P0-3.3
- **依赖**：T5（`tasks_tab` 改动后顺次落地，避免冲突）
- **改动文件**：`lib/widgets/task_card.dart`、`lib/modules/tasks/task_list.dart`、`lib/modules/tasks/tasks_tab.dart`、`test/task_card_confirm_test.dart`(新)
- **关键改动点**：
  1. `TaskCard` 加 `Future<bool> Function()? confirmDismiss`；`Dismissible.confirmDismiss: (_) async => confirmDismiss == null ? true : await confirmDismiss!()`；`onDismissed` 保持 `onDelete`。
  2. `TaskList` 加 `Future<bool> Function(Task)? confirmDismiss` 并透传给 `TaskCard`。
  3. `tasks_tab` 实现 `_confirmDelete(Task)`：`showDialog<bool>`（AppTheme AlertDialog，文案"确定删除该任务？删除后可在下方提示中撤销"，取消/删除）→ 返回 `bool`；在 `TaskList` 上传 `confirmDismiss: (t) => _confirmDelete(t)`。`selectionMode` 下 `Dismissible` 方向为 `none`，不受影响。
- **验收点**：左滑弹确认框，取消→卡片回弹不删；删除→走 `_deleteWithUndo` 并弹撤销卡；`selectionMode` 下不发生滑动删除。

### T7 · 记事本 hub 居中
- **对应**：P0-3.2
- **依赖**：无
- **改动文件**：`lib/modules/notebook/widgets/notebook_hub_card.dart`、`test/notebook_hub_card_test.dart`
- **关键改动点**：`Column(crossAxisAlignment: CrossAxisAlignment.start)` → `CrossAxisAlignment.center`（图标/标题/计数整体居中）。
- **验收点**：hub 卡内图标、标题、计数均水平居中；布局不溢出、不破坏现有间距/阴影。

### T8 · 收尾测试 + Hive 兼容校验 + 回归（含 P2-3.5 stretch）
- **对应**：P0-1.5、P2-3.5
- **依赖**：T1–T7
- **改动文件**：`lib/models/task.dart`(**确认零改动**)、`test/task_adapter_test.dart`、`test/`(全量回归)
- **关键改动点**：
  1. 确认 `task.dart` 无新增 `@HiveField`（P0-1.5）；`TaskAdapter` 读写索引 0–16 不变；`ringSeconds`@15 往返保留。
  2. 全量 `flutter test` 回归（aliyun_schedule / nlp_parser / task_card / tasks_tab / notebook_hub_card / task_feedback_card）。
  3. **P2-3.5（stretch，待确认）**：在 `TaskFeedbackCard` 上细化冲突/批量删除场景的文案与可访问性（语义色对比度、`Semantics` label），默认低优先级，范围见 §11。
- **验收点**：`task_adapter_test` 断言无新增 Hive 字段、`ringSeconds` 往返一致；全量测试通过；`flutter analyze` 无新增告警。

### 依赖关系（mermaid）
```
T1 --> T2
T1 --> T3
T4 --> T5
T5 --> T6
T2 --> T8
T3 --> T8
T5 --> T8
T6 --> T8
T7 --> T8
```

---

## 8. 依赖包列表（零新依赖）

**本增量不引入任何新第三方包。** `TaskFeedbackCard` 用 Flutter 原生 `Overlay` + `AnimatedOpacity` / `SlideTransition` 实现，不引图表/动画库。现有依赖（`flutter`/`hive`/`provider`/`http`/`yaml`/`intl`/`uuid` 等）均沿用，无需变更 `pubspec.yaml`。

---

## 9. 共享知识（跨文件约定）

1. **语义重复枚举值**（`RepeatType`）：`none`(单次) / `daily`(每天·含每晚睡前) / `weekdays`(工作日) / `weekly`(每周无具体星期) / `custom`(自定义星期)。`customWeekdays` 取值 **1=周一 … 7=周日**。YAML `repeat` 字段名与枚举字符串一一对应（`none|daily|weekdays|weekly|custom`）。
2. **YAML `output_format` 字段 ↔ 解析侧（parseJson / NlpParser）一一对应表**：

   | YAML 字段 | 解析侧键 | 映射目标 | 默认/备注 |
   |-----------|----------|----------|-----------|
   | `title` | `title` | `Task.title` | 禁含参数文本 |
   | `datetime` | `datetime`/`scheduledTime` | `scheduledTime`(绝对) | null→待安排 |
   | `remind_in_seconds` | `remind_in_seconds` | `countdownSeconds`(相对) | 与 `datetime` 互斥 |
   | `remind_in_minutes` | `remind_in_minutes`×60 | `countdownSeconds` | 折算秒 |
   | `duration_minutes` | `duration_minutes`/`durationMinutes` | `durationMinutes` | 默认 60 |
   | `resource` | `resource` | `resource` | null=无资源；单资源取首个 |
   | `repeat` | `repeat` | `RepeatType` | 默认 `none` |
   | `weekdays` | `weekdays`/`customWeekdays` | `customWeekdays` | 1–7，`custom` 时生效 |
   | `ring_seconds` | `ring_seconds` | `ringSeconds` | null/0→全局默认 5s |
   | `note` | `note` | `note` | 可选 |

3. **`TaskFeedbackCard` 三态入参约定**：
   - `success`：`message`（如"已添加 N 个任务"）+ 无 `onAction`；色=`AppTheme.accent`。
   - `delete`：`message='已删除'` + `actionLabel='撤销'` + `onAction=撤销回调`；色=`AppTheme.danger`。
   - `undo`：`message='已撤销'` + 无 `onAction`；色=`AppTheme.accent`。
   - 统一 `duration=3s`；经 `Overlay` 顶部居中浮层呈现。
4. **`ringSeconds` 回退链**：`Task.ringSeconds`(null) → `SettingsService.ringSecondsDefault`(5) → `ReminderService` 兜底 5（已存在，勿改）。
5. **标题去参双轨**：云端靠 YAML 强约束；本地靠 `NlpParser._extractCorePurpose`（剥离 提醒/倒计时/设置/时间/重复词）。任一路径产出的 `title` 均不得含参数文本。
6. **`confirmDismiss` 契约**：返回 `Future<bool>`；`false`→`Dismissible` 自动回弹不删；`true`→`onDismissed`→`onDelete`(=`_deleteWithUndo`)。`selectionMode` 下不触发。

---

## 10. 风险（R1–R8）

- **R1 · 回退一致性**：云端 YAML 升级后，本地 `NlpParser` 为降级路径，不抽 `ring_seconds`/`remind` 部分语义，可能弱于云端（如本地不抽响铃）。**缓解**：本地 `_fallback` 的 `ringSeconds` 留 null 走全局默认；标题去参规则已对齐，不会产出含参标题。
- **R2 · Overlay 与 IndexedStack 父级 Messenger 冲突**：`tasks_tab` 已用私有 `_messengerKey` 隔离 SnackBar；`TaskFeedbackCard` 用 `Overlay.of(context)`（应用级 Overlay），与 IndexedStack 不冲突。但若 `tasks_tab` 已 `dispose`（用户切 Tab），`show` 需 `mounted` 守卫，避免 `Overlay` 访问失效 context。**缓解**：`show` 内部判 `context.mounted` 且捕获 `Overlay` 空异常。
- **R3 · Dismissible 回弹动画**：`confirmDismiss` 返回 `false` 时 Flutter 自动回弹，无需手动处理；但 AlertDialog 必须 `await` 完成再 `resolve`。**缓解**：`_confirmDelete` 用 `await showDialog<bool>`。
- **R4 · ringSeconds 透传链**：`ScheduledTask.ringSeconds` → `parseJson` 读取 → `toTask` 写入 → `Task.ringSeconds`@15 → `TaskAdapter` 读写 → `ReminderService` 消费。任一环漏写都会丢响铃。**缓解**：T1/T8 用例覆盖 `ring_seconds` 全链路与 Hive 往返。
- **R5 · YAML 加载时机**：`PromptLoader.loadAll()` 在 `main.dart:53` 启动期 `await`，语音录入前必已缓存；但若 YAML 缺失/解析失败，`byId` 返回 null → 按 D1 走本地 `_fallback`（更稳）。**缓解**：不在 `_callModel` 保留内联兜底。
- **R6 · 重复枚举与 weekly**：YAML `repeat` 含 `weekly`，但 P0-1.2 推断"每周一"→`custom`、`每周`(无星期)→`weekly`；需在 YAML 规则中明确区分，避免模型把"每周一"误写 `weekly`。**缓解**：YAML 规则显式列举（见 §3-D1）。
- **R7 · Hive 兼容**：本增量 `Task` 零改动（P0-1.5），无新增 `@HiveField`；`ScheduledTask`/`ParsedTask` 非 Hive 对象，加字段不需动适配器。**缓解**：T8 断言适配器不变。
- **R8 · 测试覆盖缺口**：新增 `ring_seconds`/`resource`/`durationMinutes` 解析、本地回退透传、`TaskCard.confirmDismiss`、`TaskFeedbackCard` 生命周期均需用例，否则易回归。**缓解**：T1/T2/T4/T6/T8 配套测试。

---

## 11. 待明确事项（仅真实歧义）

1. **P2-3.5 的具体范围在所给 PRD 摘录中仅列名、未定义**。我按"反馈组件在冲突/批量删除场景的文案与可访问性细化（P2，可选）"理解，放入 **T8（stretch）**。请确认是否如此，或补充其真实定义。
2. **「每晚睡前」精确时刻映射**：我建议映射为 **23:00**（daily）。是否符合产品预期（或应为 22:30 / 23:30）？请确认。
3. **本地 `NlpParser` 资源抽取为启发式**（取首个人名/地点/会议室类 token），准确率低于云端。是否需要在本地回退时也提示"资源可能不准"？建议**不提示**，与现有 `fallback` 静默一致，请确认。
4. **本地路径是否抽取响铃时长**：口语通常不含"响铃X秒"，本地 `_fallback` 保持 `ringSeconds=null`（走全局默认 5s）。是否需要在本地也尝试抽「响铃X秒/响铃X分钟」？建议**本期不抽**（避免误判），仅云端填实，请确认。

---

*落盘文件*：
- `docs/system_design_task_enhance_2026-07-19.md`（本文）
- `docs/class-diagram-task-enhance_2026-07-19.mermaid`
- `docs/sequence-diagram-task-enhance_2026-07-19.mermaid`

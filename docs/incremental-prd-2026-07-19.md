# 增量 PRD：每日规划助手 v1.1（contemporary-opinion）

> 文档版本：v1.0 · 日期：2026-07-19 · 作者：许清楚（产品经理）
> 项目路径：`D:\code\project\contemporary-opinion`（已有 Flutter 项目，纯增量，不重写既有模块）
> 配套文档：`docs/system_design_incremental.md`、`docs/class-diagram-incremental.mermaid`

---

## 0. 范围与约束

- **本文仅描述增量变更**，不重写已有模块；新界面/改动均复用既有设计与组件。
- 技术栈沿用既有约定：Hive（JSON-map 存储，`NotebookStore` 继承 `ChangeNotifier`）、Provider、`AppTheme`（青绿强调色 `0xFF0F8C7E`）、`LabeledField`/`NotebookChip`/`DateField`/`NotebookEmptyState`/`NotebookVoiceSheet`/`SpeedDialFab`（见 `lib/modules/notebook/widgets/notebook_shared.dart`、`lib/widgets/speed_dial.dart`）。
- **任务模块必须同时覆盖两条解析路径**：①云端 `AliyunScheduleService`（通义千问）②本地 `NlpParser` 回退。两条路径对「秒级倒计时提取」和「标题提炼核心目的」行为须一致。

---

## 1. 产品目标（本增量要解决什么）

| # | 功能域 | 本增量目标 |
|---|--------|-----------|
| G1 | 任务下达修复与优化 | ①正确提取「秒」级/短倒计时提醒时间（不再用默认值）；②标题从原文提炼**核心目的**，剥离时间/提醒时长/重复等参数。 |
| G2 | 记事本·购物车子功能 | 支持创建**子购物车**归类清单；每个子购物车有**独立统计**；整体模块提供**按日/月/年筛选 + 6 区间柱状图**的统计报表。 |
| G3 | 记事本·收支账本统计报表 | 复用购物车的报表能力，对账本提供**按日/月/年筛选 + 6 区间柱状图**的可视化报表。 |
| G4 | 公共字典模块抽取 | 将旅游模块内硬编码的**交通类型 / 消费类型**字典抽取到公共模块，供账本等其它模块引用，消除三处（代码 + 两个 YAML prompt）重复定义。 |

---

## 2. 用户故事

**G1 任务下达**
- 作为用户，我语音说「设置提醒时间为10秒，去倒垃圾」，系统应在约 10 秒后提醒我，且任务标题是「去倒垃圾」而非整句原文，以便我快速核对。
- 作为用户，我语音说「明天上午9点开会，30分钟后吃药」，系统应正确拆出两个任务、标题分别为「开会」「吃药」，倒计时/绝对时间均准确。

**G2 购物车子功能**
- 作为用户，我可将购物清单按「生鲜/日用/数码」等创建子购物车，分别统计花销，避免混在一起。
- 作为用户，我想看本月/本年消费趋势，用柱状图一眼看出哪个月花得最多。

**G3 收支账本报表**
- 作为用户，我想按日/月/年查看收支走势，并和购物报表一样用 6 区间柱状图呈现。

**G4 公共字典**
- 作为用户，账本录入「分类」时直接看到与旅游一致的消费类型（餐饮/交通/购物…），无需记忆枚举。
- 作为维护者，字典只在一处定义，新增类型后所有模块自动可见。

---

## 3. 现状确认（读代码关键发现）

| 发现 | 位置 | 影响 |
|------|------|------|
| 相对时间正则仅支持 `分钟/分/min/小时/时/天/日` + `后`，**不含「秒」**；且 `秒` 无 `后` 时也匹配不到 | `lib/services/nlp_parser.dart` L77-105 | 「10秒」当前完全不被提取，回退默认值 |
| `_cleanTitle` 仅删关键词/标点/前缀，**不提炼核心目的**；「设置提醒时间为10秒，去健身房练腿」残留「设置提醒时间」 | `nlp_parser.dart` L269-285 | 标题含参数、不精炼 |
| 云端 prompt 仅要 `datetime/duration_minutes(任务时长)/resource/repeat/note`，**未要求提取短倒计时，也未要求提炼标题** | `aliyun_schedule_service.dart` L139-146 | 云端路径同样缺倒计时与标题精炼 |
| 回退 `_fallback` 把 `ParsedTask`→`ScheduledTask` 时**丢弃 countdownMinutes**；`ScheduledTask` 无 countdown 字段 | `aliyun_schedule_service.dart` L188-198 | 倒计时在云端失败回退时丢失 |
| `Task.countdownMinutes` 仅分钟级（`HiveField(3)`）；`ringSeconds` 是响铃时长，非倒计时 | `lib/models/task.dart` L47, L90 | 不支持秒级倒计时存储 |
| `NotebookShopping`/`NotebookLedger` 均为**扁平模型**，无子购物车/分组概念 | `notebook_shopping.dart`、`notebook_ledger.dart` | G2/G3 需新增分组与报表模型 |
| `kTransportModes`/`kBillingTypes` 硬编码在 `notebook_trip.dart` 顶部 | `notebook_trip.dart` L7-24 | G4 需抽取 |
| `kBillingTypes` 同时被 `notebook_voice_trip.yaml` 的 `<dictionaries>` **重复硬编码**；`notebook_voice_ledger.yaml` 的 `category` 为自由文本 | 两个 YAML | G4 需统一来源 |
| **无图表库**（pubspec 无 fl_chart/charts_flutter） | `pubspec.yaml` | 柱状图需自绘或新增依赖（见 Q4） |

---

## 4. 需求池

> 优先级：P0 必须 / P1 重要 / P2 可选增强。每条带【验收标准】。

### 功能域一：任务下达修复与优化（G1）

**P0-1.1 秒级/短倒计时提取——本地 NlpParser 路径**
- 扩展相对时间匹配，支持 `秒` 单位；兼容两种口语：「X秒后」「提醒时间(为)X秒/分/时」。
- 倒计时精度提升至秒：`ParsedTask` 新增 `int? countdownSeconds`（保留现有 `countdownMinutes` 兼容）；`scheduledTime = now + Duration(seconds: countdownSeconds)`。
- 【验收】输入「设置提醒时间为10秒，去倒垃圾」→ 生成 Task，`scheduledTime ≈ now+10s`、`countdownSeconds=10`、标题不含「10秒」。回归：输入「30分钟后吃药」仍 `= now+30min`；输入「明天上午9点开会」scheduledTime 正确。

**P0-1.2 秒级/短倒计时提取——云端路径**
- 修改 `_callModel` 的 system prompt：当用户给出提醒时间/倒计时时，要求模型输出 `remind_in_seconds`（相对 now 的整数秒，或 `remind_in_minutes`）。`parseJson` 据此计算 `scheduledTime = now + 秒` 并写入倒计时字段。
- 【验收】云端可用态下同一输入与本地行为一致；云端返回倒计时时正确折算绝对时间。

**P0-1.3 回退链路透传倒计时**
- `ScheduledTask` 新增 `int? countdownSeconds`；`_fallback` 透传 `ParsedTask.countdownSeconds`；`parseJson` 同样填充。
- `Task` 模型新增 `int? countdownSeconds`（`HiveField(16)`），同步更新 `TaskAdapter.read/write`（缺失该字段的老数据读回为 null，不影响）；`toTask` 透传。
- 【验收】云端失败回退时 10 秒倒计时不丢失；升级后旧任务数据正常加载、不崩溃。

**P0-1.4 标题提炼核心目的——本地 NlpParser._cleanTitle**
- 在现有「删关键词/标点/前缀」之后新增**核心目的抽取**：移除时间表达式（X秒/X分钟/X点/明天…）、提醒时长/倒计时短语（提醒时间/提醒/倒计时…）、重复词（每天/每周…），取剩余动作片段为核心标题；若抽取为空则回退原 `_cleanTitle`。
- 【验收】输入「设置提醒时间为10秒，去健身房练腿」→ `title='去健身房练腿'`（不含「设置提醒时间」「10秒」）；输入「明天上午9点开会」→ `title='开会'`。提供 ≥5 条 fixture 单测。

**P0-1.5 标题提炼核心目的——云端 prompt**
- 修改 `_callModel` system prompt：明确「title 必须是任务【核心目的/动作】，禁止包含触发时间、提醒时长、重复等参数；例：'设置提醒时间为10秒，去健身房练腿' → title='去健身房练腿'」。
- 【验收】云端返回 `title` 不携带时间/提醒参数。

**P1-1.6 语音预览强化（voice_input_screen.dart）**
- `_PreviewTile` 在短倒计时时显示「10秒后 / 倒计时」徽标（复用 `NotebookChip` / `AppTheme.warn`），与绝对时间文案（`_formatTime`）并存，便于用户核对。
- 【验收】预览页对 10 秒任务显示明确倒计时提示。

**P2-1.7 解析一致性测试**
- 为 `NlpParser` 与 `ScheduledTask.parseJson` 增加参数化测试，覆盖 秒/分/时/天 + 标题抽取的双路径一致性。

### 功能域二：购物车子功能（G2）

**P0-2.1 数据模型：子购物车容器**
- 新增 `NotebookShoppingCart`（字段：`id` / `name` / `createdAt` / 可选 `note`）；`NotebookShopping` 增加 `String cartId`（空 `''` = 未分组/默认车）。
- `NotebookStore` 新增 `notebook_shopping_carts` 盒子（JSON-map），暴露 `shoppingCarts` getter 及 `addCart/updateCart/deleteCart`；`shopping` 增加按 `cartId` 分组能力（或在 UI 层分组）。
- 【验收】可创建子购物车并归属购物项；Hive 读写正常。

**P0-2.2 迁移既有扁平数据**
- 首次访问时，将 `cartId==''` 的既有购物项归入默认「未分组」分组（或自动建一个默认子购物车），**不丢数据**。
- 【验收】升级后旧购物项仍可见可用、无崩溃。

**P0-2.3 子购物车独立统计**
- 每个子购物车展示：项数、`ΣexpectedPrice`、`ΣactualPrice`、差额；UI 复用 `_Row` 卡片样式 + `NotebookChip` 标签 + `AppTheme.accent` 金额色。
- 【验收】统计值 = 该 `cartId` 下各项聚合，与明细一致。

**P0-2.4 整体购物统计报表（日/月/年 + 6 区间柱图 + 可选起点）**
- 新增报表视图：粒度切换（日/月/年）；按粒度聚合 `actualPrice` 总额；柱图**恒为 6 个区间**（最近 6 日/月/年），用户可前后选择「起始月/年」；底部柱状图可视化花费趋势。
- 实现：无图表库 → 轻量自绘柱状图（6 个 `Container` 高度映射 + 坐标轴标签/数值，复用 `AppTheme` 语义色与 `radiusLg`）；或引入 fl_chart（见 Q4）。空态用 `NotebookEmptyState`。
- 【验收】切换日/月/年正确聚合；柱图恒 6 区间；可改起始月/年；数值与底层一致。

**P1-2.5 子购物车创建/编辑/删除 UI**
- `ShoppingDetail` 顶部/分组区提供「新建子购物车」（复用 `LabeledField` + 既有 `SpeedDialFab` 模式）；子购物车卡片点击进入该购物车明细列表（复用 `_Row`）。
- 【验收】可增删改子购物车并即时反映于列表与统计。

**P2-2.6 子购物车语音归类（可选）**
- 语音录入购物项时支持指定子购物车（扩展 `notebook_voice_shopping.yaml` 与 `NotebookVoiceService.parseShopping` 透传 `cartId`）。可后置。

### 功能域三：收支账本统计报表（G3）

**P0-3.1 整体账本统计报表（与购物车同源）**
- 抽离购物报表为**共享组件/工具**（如 `lib/modules/notebook/widgets/notebook_report.dart` 的 `_StatsReport`），对 `ledger` 按日/月/年聚合 `amount`（收入/支出/结余分色，`AppTheme.ok`/`AppTheme.danger`），6 区间柱图、可选起点，行为同 G2。
- 【验收】账本报表与购物报表一致；按 `kind` 正确配色；空态正确。

**P1-3.2 账本时间维度补全**
- 报表依赖 `date`：`ledger.date` 在手动与语音录入均默认录入当日（现有为可选），以支撑按日统计。
- 【验收】无 `date` 条目按录入日归入当日统计，不丢。

**P2-3.3 账本按消费类型二级统计（可选）**
- 报表中按 `category`（公共字典）分组占比。

### 功能域四：公共字典模块抽取（G4）

**P0-4.1 抽取公共字典模块**
- 新建 `lib/models/dictionary.dart`，导出 `kTransportModes`、`kBillingTypes`（保持现有取值与顺序不变）；`notebook_trip.dart` 改为从 `dictionary.dart` 导入并删除文件内硬编码 const。
- 【验收】编译通过；trip 模块 `ChoiceChip`/`FilterChip` 渲染与现状一致。

**P0-4.2 收支账本引用公共消费字典**
- `ledger` 手动录入表单「分类」改为从 `kBillingTypes` 选择（`NotebookChip`/`ChoiceChip` 单选，含「其他」）；自由输入作为 P2。
- 【验收】账本分类来自公共字典；字典新增项账本自动可见。

**P1-4.3 字典同步到语音 prompt**
- 更新 `notebook_voice_trip.yaml` 的 `<dictionaries>` 段与 `notebook_voice_ledger.yaml` 的 `category` 规则，引用同一公共字典值；理想方案（P2）：`PromptLoader` 加载时注入字典常量，避免代码 + 两个 YAML 三处不一致。
- 【验收】语音产出的 transport/billing/category 取值 ∈ 公共字典。

**P2-4.4 字典可配置/可扩展（可选）**
- 支持设置页增删字典项并持久化，各引用点动态读取。

---

## 5. UI 设计要点（草图级，引用可复用组件）

> 风格统一：发丝边框 + 扩散阴影卡片、`AppTheme` 圆角（10/14/20）与语义色、完整空/错/加载态。

### 5.1 任务语音预览（改动，`voice_input_screen.dart`）
```
┌─ 解析出 2 项 ────────────────────┐
│ [✓] 去倒垃圾          🟠10秒后     │   ← 新增倒计时徽标（NotebookChip, warn）
│     今天 14:32                      │
│ [✓] 吃药             ⏰30分钟后     │
└───────────────────────────────────┘
```
- 仅 `_PreviewTile` 增加倒计时徽标；其余不变。

### 5.2 购物清单（子购物车 + 报表，`shopping_detail.dart`）
```
AppBar[购物清单]   [📊报表]            ← 新增报表入口
─────────────────────────────────────
[🛒 生鲜]  3 件 · 实付 ¥128          ← NotebookShoppingCart 卡片(复用_Row样式)
[🛒 日用]  5 件 · 实付 ¥240
[未分组]   2 件 · 实付 ¥30            ← 默认/迁移分组
─────────────────────────────────────
(FAB: SpeedDialFab → 手动录入 / 语音录入)
```
- 子购物车卡片点击 → 该购物车明细列表（复用 `_Row`）。
- 报表页（`_StatsReport`）：顶部 `[日|月|年]` 分段选择 + `起始：<月/年选择器>`（`DateField` 思路）；中部 6 根柱状图（自绘 `Container` 高度映射），底部合计/均值。

### 5.3 收支账本报表（`ledger_detail.dart`）
- 在现有 `_Summary`（收入/支出/结余）下方或独立报表页复用 `_StatsReport`；柱图按 `kind` 分色（收入 `ok` / 支出 `danger`）。手动表单「分类」改 `kBillingTypes` 单选 chips。

### 5.4 子购物车编辑/统计
- 新建/编辑子购物车：底部弹层复用 `LabeledField`（名称*）+ `FilledButton` 保存，沿用 `showModalBottomSheet` 现有形态。

### 5.5 公共字典引用点
- `trip_detail.dart` `_CheckpointEditSheet`：`kTransportModes`/`kBillingTypes` 改为从 `dictionary.dart` 导入（调用处不变）。
- `ledger_detail.dart` `_LedgerAddSheet`：「分类」`LabeledField` 替换为 `kBillingTypes` 的 `ChoiceChip` 单选行。

---

## 6. 待确认问题（需技术/产品拍板）

1. **Q1 倒计时双路径责任**：云端模型能否稳定返回 `remind_in_seconds`？建议**云端 + 本地双覆盖**，云端失败时本地兜底保证可用（已在 P0-1.1~1.3 覆盖），请确认此策略。
2. **Q2 子购物车数据模型与迁移**：推荐 **「外键 `cartId` + 独立 `carts` 盒子」**（增量最小、迁移最简单，旧数据 `cartId=''` → 默认分组）；备选「容器模型 `NotebookShoppingCart.items`」。请架构师拍板。
3. **Q3 Task 模型字段**：新增 `countdownSeconds`（`HiveField(16)`）是否足够？是否保留/废弃 `countdownMinutes`？需确认 Hive 兼容与 `flutter_local_notifications` 最小调度间隔（秒级是否可行）。
4. **Q4 柱状图实现**：引入 `fl_chart` 等新依赖，还是**自绘无新依赖**（契合现有轻量风格、6 根柱足够）？建议自绘。
5. **Q5 公共字典形态**：本增量取「代码 const 单一来源」（P0-4.1/4.2）；是否需设置页可编辑（P2-4.4）？trip/ledger 两个 YAML prompt 如何与代码字典保持同步（P1-4.3 / P2 注入）？

---

## 7. 影响面与文件改动索引（增量）

| 文件 | 关联需求 |
|------|----------|
| `lib/services/nlp_parser.dart` | P0-1.1, P0-1.4 |
| `lib/services/aliyun_schedule_service.dart` | P0-1.2, P0-1.3, P0-1.5 |
| `lib/models/task.dart` + `TaskAdapter` | P0-1.3 |
| `lib/models/notebook_shopping.dart` | P0-2.1 |
| `lib/models/dictionary.dart`（**新增**） | P0-4.1 |
| `lib/models/notebook_trip.dart` | P0-4.1 |
| `lib/services/notebook_store.dart` | P0-2.1, P0-2.2 |
| `lib/modules/notebook/screens/shopping_detail.dart` | P0-2.3~2.5 |
| `lib/modules/notebook/screens/ledger_detail.dart` | P0-3.1, P0-3.2, P0-4.2 |
| `lib/modules/notebook/widgets/notebook_report.dart`（**新增，共享报表**） | P0-2.4, P0-3.1 |
| `lib/modules/tasks/voice_input_screen.dart` | P1-1.6 |
| `assets/prompts/notebook_voice_ledger.yaml` / `notebook_voice_trip.yaml` | P1-4.3 |

---
*注：本 PRD 为「简单 PRD 级别」，聚焦增量变更与可验收标准，供架构师拆分任务使用；完整竞品/象限分析不在本增量范围。*

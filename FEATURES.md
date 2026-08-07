# 时说 (daily_planner) 完整功能清单

> **单一权威文档**（合并自原多份清单，避免分散）。
> 面向 AI 编程工具 / 接手者：说清每个模块做什么、有哪些字段与交互、技术约定与提示词。
>
> **平台定位**：基于 Flutter 的**移动端应用（Android / iOS）**；本地 **SQLite** 存储；本地登录验证、无后端；移动端适配为第一优先级。
> **本轮设计变更**：① 记事本模块移除语音，仅手动新增；② 存储由 Hive/JSON-map 改为 SQLite（sqflite）；③ 新增登录与用户管理（本地校验）；④ 已登录用户不再每次展示品牌启动页，直接进任务列表；⑤ 移除全部 Web 录音/通知/兜底，纯移动端。

---

## 〇、平台与全局约定

| 项 | 约定 |
|----|------|
| 平台 | Flutter 移动端（Android / iOS），锁定竖屏，纯移动端、无 Web |
| 本地存储 | **SQLite（sqflite）**；`DatabaseHelper` 单例统一建表/迁移/读写；业务表均带 `user_id` 归属当前登录用户 |
| 状态管理 | Provider（`TaskStore` / `NotebookStore` 均 `ChangeNotifier`） |
| 主题 | `theme/app_theme.dart`，浅/深自适应（`ThemeMode.system`）；单一强调色 + 完整交互态 |
| 语音 | **仅任务模块**使用 `AliyunAsrService`（Qwen3-ASR-Flash）+ `AliyunScheduleService`（qwen3.7-max）；记事本已移除语音 |
| 移动端适配 | `SafeArea`、触控目标 ≥44pt、权限请求（麦克风 `RECORD_AUDIO` / 通知 `POST_NOTIFICATIONS`）、原生通知与录音、手势（滑动删除/下拉刷新） |

---

## 一、登录与用户管理（Login & User）`[新增 · 本地校验]`

**定位**：本地账户体系，注册/登录/用户信息管理全部在设备端完成，无网络请求、无后端。

- **存储（SQLite）**
  - `users`：`id` / `username`(UNIQUE) / `password_hash` / `nickname` / `avatar_path` / `default_ring_seconds` / `created_at`
  - `session`（单行，`id` 固定 1）：`user_id` / `is_logged_in`，持久化当前登录态
  - 密码做哈希（如 `sha256(salt+password)`）后存 `password_hash`；校验时同样哈希比对，不存明文
- **功能**
  - 注册：用户名 + 密码；校验用户名唯一；可选昵称、头像
  - 登录：用户名 + 密码匹配本地 `users` 即通过，写 `session`；失败给明确错误提示
  - 用户信息管理：个人页编辑昵称、选本地头像（`image_picker`）、设默认响铃时长 `default_ring_seconds`（新建任务默认用）
  - 登出：清空 `session`，下次启动回登录页
- **移动端适配**：密码框 `obscureText` + 显隐切换；`keyboardType` 合理；按钮触控尺寸达标
- **路由守卫**：App 启动读 `session`——已登录直接进任务列表页；未登录进登录/注册页

---

## 二、启动流程与路由

- **品牌启动页（SplashScreen）**：仅在「未登录首次启动」展示品牌「时说」+ 标语，短暂（~1.2s）后跳登录页
- **已登录**：启动直接进**任务列表页（TasksTab）**，跳过品牌页（极短加载态即可，不展示品牌）
- **路由**：未登录 → `LoginPage` ⇄ `RegisterPage`；已登录 → `MainPage`（底部 Tab：任务 / 记事本 / 我的）
- **移动端适配**：首屏 `SafeArea`；适配刘海/挖孔；锁定竖屏

---

## 三、任务模块（Tasks）

**定位**：用说的 / 手填都能建日程；核心是「资源占用冲突检测 + 移动端系统级精确提醒」。

### 3.1 数据模型（SQLite 表 `tasks`）
`Task` 纯 Dart 模型（`toMap()` / `fromMap()`），无 Hive Adapter；关键列：
- `title` 标题
- `scheduled_time` 绝对触发时间（ISO8601；倒计时任务创建时即折算为「现在+分钟」）
- `countdown_minutes` / `countdown_seconds` 倒计时原始值（仅展示）
- `repeat`：`none` / `daily` / `weekly` / `weekdays` / `custom`
- `custom_weekdays` 自定义星期（JSON `[1..7]`，1=周一…7=周日）
- `status`：`pending` / `done` / `missed`（一次性过期未处理标 missed）
- `source`：`manual` / `voice`
- `resource` 资源（如「会议室A」「车」），冲突检测用；空=无资源
- `duration_minutes` 时长（默认 0=仅提醒不占时段；冲突按「时段」判）
- `ring_seconds` 响铃时长（null=用用户默认或全局默认）
- `conflict_state`：`none` / `pendingConflict` / `confirmedOverride` / `undated`
- `effective` 是否生效（0/1）；冲突待处理时为 0
- `notification_id` 通知 id（重复任务派生多个子 id）
- `completed_at` / `note` 备注
- 持久化：`TaskDao` 经 sqflite 读写

### 3.2 录入方式
**A. 手动（`modules/tasks/add_task_screen.dart`）**
- 分区表单：基本信息（标题）/ 提醒设置 / 资源与时长
- 提醒 `SegmentedButton`：指定时间（日期+时刻）｜倒计时（分钟）
- 重复 `Dropdown` + 自定义星期 `ChoiceChip` 多选
- 资源、时长（分）、响铃（秒，可空）
- 校验：非倒计时开始时间不早于当前（过去时间 SnackBar 拦截）
- 新建走 `addWithConflictCheck`；编辑走 `recheck`；编辑页有「确认覆盖冲突并生效」

**B. 语音规划（`modules/tasks/voice_input_screen.dart`）**
- 流程：录音（`record` 采集麦克风 PCM，首次请求 `RECORD_AUDIO`）→ `AliyunAsrService` 转写 → 排期模型（`tasks_voice_scheduled` / `tasks_voice_delay` 按意图选）解析 → 逐个 `ConflictDetector.detect` + `applyDecision`
- 预览页：每条任务一张卡可勾选，展示时间/倒计时/重复/资源/时长/响铃
- 四视觉态：冲突待处理（红框+三按钮 确认覆盖/改时间/换资源）/ 时间待定（黄框 设时间才提醒）/ 仅时间重叠（黄字弱提醒，正常生效）/ 过去时间（红框 保存跳过）
- 返回 `{added, conflict, skipped}`，由 TasksTab 用 `TaskFeedbackCard` 统一展示
- 离线兜底：无云端 key 时 `nlp_parser.dart` 本地解析中文时间（绝对/倒计时/重复/模糊词如"大后天"），输出同结构任务

### 3.3 冲突检测（`services/conflict_detector.dart`，纯 Dart 可单测）
- 时段重叠 ⟺ `a.start < b.end && b.start < a.end`；时长 0 按最小 1 分钟参与重叠
- **资源占用冲突** = 时间重叠 **且** 两任务 `resource` 归一化（去空格小写）后相等且非空
- 阻断口径：仅资源占用冲突算「阻断」→ `pendingConflict` / `effective=0`；纯时间重叠仅弱提醒、正常生效
- 三种处理：改时间 / 换资源（重检无冲突自动恢复生效）/ 确认覆盖（`confirmOverride` 强制生效）
- 重复任务按「未来 30 天窗口」近似展开；已完成(done)不占资源、无时间 backlog 不参与
- 无时间候选 → `undated` / `effective=0`（强制补时间才生效）

### 3.4 提醒调度（`services/reminder_service.dart`）
- 移动端：`flutter_local_notifications` + `exactAllowWhileIdle` 系统级精确调度（应用被杀仍弹）；`timezone` 锁 `Asia/Shanghai`
- 权限：首次进入请求 `POST_NOTIFICATIONS`（Android 13+）/ iOS 授权；被拒引导设置
- 应用存活：`Timer` 到点触发「响铃（`audioplayers`/本地音频）+ 中文 TTS 循环播报」（`_voiceLoopTotal`=10s、间隔 2s），可取消立即中断
- 重复任务：按 `repeat` 派生多通知 id + `matchDateTimeComponents` 重发；in-app Timer 续约
- `scheduleAll()` 启动重排；`notifyTaskChanged()` 完成取消、否则重排
- **已移除 Web 兜底**（纯移动端）

### 3.5 列表与交互（`tasks_tab.dart` + `task_list.dart` + `task_card.dart`）
- 顶部 `FilterTabBar`：全部 / 进行中 / 待办 / 逾期 / 冲突 / 已完成（带数量角标）
- `Speed Dial`：手动新增 + 语音规划
- 勾选完成：一次性切 done/pending；**重复任务「完成今天这一次」**——种子滚动到下次发生、保持 pending、记 `completed_at` 供今日显示、次日跨日自动恢复
- 删除：滑动删除+二次确认；长按进选择模式批量删（先取消提醒再删）
- 冲突卡红框 + 徽标 + 「确认覆盖」按钮
- 移动端：`SafeArea`、触控目标充足、滑动手势

---

## 四、记事本模块（Notebook）`[已移除语音 · 仅手动]`

**定位**：六大生活记录子功能，**仅手动录入**；2 列网格 hub 入口。

### 4.1 存储与入口（SQLite）
- 入口 `modules/notebook/notebook_tab.dart`：2 列网格（`NotebookHubCard`）显示各子功能条目数；录入在各子功能详情页
- 各子功能独立表（取代原 Hive JSON-map）：
  - 购物：`shopping_carts(id, user_id, name, note)` + `shopping_items(id, cart_id, item, expected_price, actual_price, category, note, date)`
  - 收支：`ledger(id, user_id, title, kind, amount, category, date, note)`
  - 读书：`reading(id, user_id, title, author, status, rating, category, note)`
  - 旅游：`trips(id, user_id, title, city, home_city, start_date, end_date, intercity_transport(JSON), hotel(JSON), transports(JSON), total_cost)` + `trip_days(id, trip_id, date, label)` + `trip_checkpoints(id, day_id, name, transport(JSON), billings(JSON), done, rating, note)`
  - 学习：`courses(id, user_id, title, source, status, progress, rating, category, note)` + `study_records(id, course_id, title, content, rating, note, created_at)`
  - 菜谱：`recipes(id, user_id, name, category, ingredients(JSON), steps(JSON), difficulty, rating, note)`
- `NotebookStore`（Provider）封装各表 DAO，变更后 `notifyListeners()`
- **录入方式：仅手动表单**（已移除 `NotebookVoiceSheet` 语音录入及 6 份 `notebook_voice_*.yaml` 提示词）

### 4.2 六大子功能（均仅手动）
**① 购物清单** — 子购物车分组 + 购物项（物品/预期价/实际价/分类/备注/`cart_id`/日期）；按购物车聚合显示 项数/预期/实付/差额（≥0 绿、否则红）；删购物车其项回收「未分组」不丢数据；详情页「报表」→ 消费趋势图

**② 收支账本** — 条目：标题/`kind`(income/expense)/`amount`/分类/日期/备注

**③ 读书清单** — 条目：书名/作者/`status`(want/reading/done)/`rating`(1–5)/分类/备注

**④ 旅游行程** — 嵌套：城际交通 `intercity_transport`、酒店 `hotel`、其余交通 `transports[]`、每日 `trip_days[]{checkpoints[]}`；打卡点 `trip_checkpoints`（名称/交通/计费 `billings[]`/打卡 `done`/`rating`/备注）；`total_cost` 本地实时汇总（城际×往返×次数 + 酒店×晚数 + 各打卡点计费），金额用户手填；交通/计费枚举见 `dictionary.dart`

**⑤ 学习记录** — 以课程为维度：`courses`（标题/来源/状态/进度 0–100/评分/分类/备注）+ 名下 `study_records[]`（标题/内容/评分/备注/创建时间）；课程列表 → 进课程 → 追加记录

**⑥ 菜谱收藏** — 条目：菜名/分类/`ingredients[]`/`steps[]`/`difficulty`(easy/medium/hard)/评分/备注

### 4.3 可视化报表统计（`widgets/notebook_report.dart`）
- 自绘柱状图，零第三方图表库：6 个 `Container` 拼柱，`StatsReport` 按最大桶高等比缩放；无数据走 `NotebookEmptyState`
- 输入原子 `ReportDatum{date, value, kind}`：购物传 `date`+`value`（主序列）；账本传 `date`+`value`+`kind`(income/expense)，收入绿/支出红堆叠
- 桶聚合 `buildStatsBuckets(data, granularity, anchor)`：空 `date` 填今日 → 周期 key 累加；恒 6 桶
- 粒度 `day`(M/d) / `month`(M月) / `year`(yyyy)；窗口 `[anchor-5 … anchor]`，自动月/年进位
- 页面 `ReportScreen`：上/下区间 `IconButton` + `SegmentedButton` 日/月/年；账本→收支报表，购物→消费报表；数值前缀 `unit`(¥)
- 移动端：图表宽按 `MediaQuery` 自适应

### 4.4 共享组件（`widgets/notebook_shared.dart`）
`NotebookEmptyState` / `LabeledField` / `StarsRow`(0–5) / `NotebookChip` / `DateField`(yyyy-MM-dd) / `ReportScreen`；表单用移动端输入（金额/评分数字键盘，日期走原生 `showDatePicker`）

---

## 五、提示词工程（任务模块定稿 YAML）

> 仅保留**任务模块** 2 份提示词（记事本语音已移除，6 份 YAML 不再使用）。直接注入 LLM 的 system/解析提示词。
> 统一约定：只输出纯 JSON（禁 ``` 包裹/前后解释）；命名类字段禁含触发参数；标题温柔贴心（以「你」起头）；可空填 `null`、空数组 `[]`；键名严格一致；系统注入 `<current_time>` 作时间基准。

### 5.1 任务·设定时间的任务（`tasks_voice_scheduled`）
```yaml
id: tasks_voice_scheduled
module: tasks
type: voice
description: 语音录入「设定时间的任务」的排期解析提示词（按绝对/相对时刻排期，时长默认 0 只做提醒，不含任何倒计时字段）
prompt: |
  <role>你是一个日程规划助手，负责把用户的一段中文口语转写，解析为结构化任务列表。本提示词专用于「设定时间的任务」：用户表达的是某个具体时刻（今天 / 明天 / 周几 + 时间点）要去做的事。</role>
  <task>
  1. 任务拆解（按「语义时间锚点」拆分，而非标点）：每个「时间锚点 + 动作」单元 = 一条任务；同一锚点下并列动作各拆一条；标点仅辅助。
  2. 时间推算：每锚点推绝对日期时间填 datetime（yyyy-MM-dd HH:mm）。
  3. 资源识别：提取 resource（仅一个主要资源，无则 null）。
  4. 重复识别：填 repeat 与 weekdays。
  5. 时长识别：仅显式说「持续/历时/花费 N 分钟|小时」才填 duration_minutes；默认 0。
  6. 响铃：显式说「响铃 N 秒|分|时」折秒填 ring_seconds；未提填 null。
  7. 忽略闲聊；至少可输出 0 个任务。
  </task>
  <examples>
  输入：我下周一，下午三点，需要和朋友出去玩儿，你需要设置一个十秒钟的提醒时间。我明天上午十点，需要写作业，请你设置一个二十秒的提醒时间。
  输出：{"tasks":[{"title":"你要和朋友出去玩儿啦，好好放松一下","datetime":"2026-01-12 15:00","duration_minutes":0,"resource":null,"repeat":"none","weekdays":[],"ring_seconds":10,"note":null},{"title":"你有一项作业要写，记得按时完成哦","datetime":"2026-01-09 10:00","duration_minutes":0,"resource":null,"repeat":"none","weekdays":[],"ring_seconds":20,"note":null}]}
  输入：每天早上八点去公园跑步，响铃一分钟。
  输出：{"tasks":[{"title":"你打算去公园跑步啦，动动身体更健康","datetime":"2026-01-08 08:00","duration_minutes":0,"resource":null,"repeat":"daily","weekdays":[],"ring_seconds":60,"note":null}]}
  </examples>
  <output_format>{"tasks":[{"title":字符串,"datetime":"yyyy-MM-dd HH:mm" 或 null,"duration_minutes":整数(默认0),"resource":字符串或null,"repeat":"none|daily|weekdays|weekly|custom","weekdays":[1-7的整数]或[],"ring_seconds":整数或null,"note":字符串或null}]}</output_format>
  <format_constraints>只输出纯 JSON；title 严禁含触发参数、温柔贴心（以「你」起头）；可空填 JSON null；repeat 仅取 none|daily|weekdays|weekly|custom；weekdays 空填 []；键名严格一致。</format_constraints>
  <critical_reminders>按语义时间锚点拆分；datetime 必须绝对时间，无法确定才 null（进入 undated 不生效）；duration_minutes 默认 0；ring_seconds 默认 null；重复：每天→daily；周一三五→custom+weekdays；工作日→weekdays；每周→weekly；单次→none；严禁输出 remind_in_seconds/minutes。</critical_reminders>
```

### 5.2 任务·延时任务（`tasks_voice_delay`）
```yaml
id: tasks_voice_delay
module: tasks
type: voice
description: 语音录入「延时任务」的排期解析提示词（仅相对提醒倒计时，无 datetime/resource/repeat/weekdays/duration 字段）
prompt: |
  <role>你是一个延时提醒助手，负责把用户的一段中文口语转写，解析为「相对时间后提醒」的结构化任务列表。本提示词专用于「延时任务」：用户说“过一会儿 / X 秒后 / X 分钟后”，无具体钟点。</role>
  <task>
  1. 任务拆解（按「语义动作」拆分）：每动作一条，宁可多拆。
  2. 倒计时识别（核心）：从「X 秒后/分钟后/小时后」折秒填 remind_in_seconds（分×60、时×3600）；可用 remind_in_minutes 表整分钟；无绝对时刻。
  3. 响铃：显式说「响铃 N 秒|分|时」折秒填 ring_seconds；未提填 null。
  4. 忽略闲聊；至少可输出 0 个任务。
  </task>
  <examples>
  输入：十秒后关火，响铃五秒。三十分钟后吃药。
  输出：{"tasks":[{"title":"你该去关一下火啦，注意安全","remind_in_seconds":10,"remind_in_minutes":null,"ring_seconds":5,"note":null},{"title":"你该吃药啦，记得按时服用","remind_in_seconds":1800,"remind_in_minutes":30,"ring_seconds":null,"note":null}]}
  输入：两小时后去取快递，响铃十秒。
  输出：{"tasks":[{"title":"你有一个快递需要去拿一下","remind_in_seconds":7200,"remind_in_minutes":null,"ring_seconds":10,"note":null}]}
  </examples>
  <output_format>{"tasks":[{"title":字符串,"remind_in_seconds":整数(必填,>0),"remind_in_minutes":整数或null,"ring_seconds":整数或null,"note":字符串或null}]}</output_format>
  <format_constraints>只输出纯 JSON；title 严禁含倒计时/响铃参数、温柔贴心（以「你」起头）；可空填 JSON null；本提示词只处理倒计时，严禁输出 datetime/resource/repeat/weekdays/duration_minutes；键名严格一致。</format_constraints>
  <critical_reminders>按语义动作拆分；remind_in_seconds 必填且 >0（分×60、时×3600）；本提示词只处理倒计时；ring_seconds 默认 null，仅显式说「响铃」才填。</critical_reminders>
```

---

## 六、生产化 / 待补（可选）

| ID | 项 | 说明 | 优先级 |
|----|----|------|--------|
| P1 | 后端代理密钥 | 若做云端，生产改后端/云函数持 key，前端只拿短期 token（当前本地验证，非必需） | P1 |
| P1 | RRULE 精确重复 | 重复任务冲突检测改标准 RRULE 精确展开（现近似 30 天窗口） | P1 |
| P1 | 应用商店长描述 | 补齐上架长描述（功能详解/截图文案/隐私说明）；`docs/brand_design.md` 已有约 110 字简介可作开篇 | P1 |
| P2 | 多语言 i18n | 引入 `intl`，至少中英双语 | P2 |
| P2 | 桌面端 + Widget | 后续多端扩展（当前为移动端，非必需） | P2 |

---

## 附：功能速览表

| 模块 | 功能 | 要点 |
|------|------|------|
| 登录 | 注册/登录/用户信息 | 本地校验、密码哈希、session 持久化、user_id 隔离 |
| 启动 | 品牌启动页 | 仅未登录首启；已登录直达任务列表 |
| 任务 | 语音+手动录入 | ASR(Qwen3-ASR-Flash)→排期(qwen3.7-max)→冲突预览；离线 NLP 兜底 |
| 任务 | 冲突检测 | 资源占用=阻断；三种处理；30 天近似展开 |
| 任务 | 提醒调度 | 移动端系统级精确通知 + in-app 响铃/TTS；权限请求 |
| 任务 | 列表交互 | 筛选/选择模式/重复「完成今天」滚动 |
| 记事本 | 六大子功能 | 购物/账本/读书/旅游/学习/菜谱；SQLite 独立表；仅手动 |
| 记事本 | 可视化报表 | 自绘柱状图、日/月/年、收支堆叠/购物趋势 |
| 全局 | 存储/状态/主题 | SQLite + Provider + 浅深自适应 |
| 全局 | 移动端适配 | 竖屏/SafeArea/权限/触控/手势 |

---

## 2026-08-06 任务模块 V3 变更（冒烟整改）

### 状态与列表
- 状态收敛为 4 个 Tab：**全部 / 进行中 / 冲突 / 已完成**；移除「待办」「逾期」。
- 进行中 = 当前还需要执行的任务（执行窗口内 + 未来待执行 + 倒计时重复链），**不含冲突任务**。
- 已完成只展示**不再执行的死任务**（一次性完成 / 倒计时重复达上限 / 周期结束）。
- 所有列表按**创建时间降序**。

### 任务记录与详情
- 记录行 = 状态图标 + 单行标题（省略） + 单行元信息；冲突仅红色标记。
- 点击记录进**详情抽屉**：字段可直接编辑（时间/时长/资源/响铃、倒计时间隔/次数），
  冲突原因卡提供「确认覆盖 / 改时间换资源」；单一「完成」保存自动返回；完成/恢复操作收进详情。
- 长按多选 → 底部「删除（N）/ 取消」双按钮批量删除。

### 语音规划（同页浮层）
- 录音不跳转页面，底部浮层内完成；可先打字，**录音内容追加到光标处**不覆盖。
- 停止键为单层环 + 红方块；上方耳朵 + 音波动效（振幅随音量）。
- 排期结果同浮层展示，冲突条目红色标记；逐条保存容错（修复多任务只保存一个）。

### 调度表结构 v3（对齐 task_schedule）
- tasks 表新增：`trigger_type`(once/recurring/delayed)、`freq_type`/`freq_interval`/`end_at`、
  `interval_seconds`/`max_repeats`/`repeat_count`、`next_fire_time`/`prev_fire_time`。
- 倒计时任务改为**每 N 分钟 × M 次**（DELAYED），不再有每天/每月概念。

### 铃铛提醒设置
- 首页铃铛打开「提醒方式」：静音 / 语音播报互斥，震动独立开关可叠加，音量滑杆。
- 设置持久化 `user_settings`；静音到点不播报，语音音量作用于 TTS。
- **提醒链路修复**：`ReminderService.init + scheduleAll` 已在登录后接线（此前从未被调用）。

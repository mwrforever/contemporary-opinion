# 任务模块整改实施计划

> **For agentic workers:** 按本文档任务逐项实施；步骤使用 `- [ ]` 跟踪。本计划基于已批准的设计稿 `design/ui-mockup-task-v2/index.html` 与主理人口径（2026-08-06 确认）。

**Goal:** 落地任务模块冒烟问题整改：状态语义收敛、列表/详情/语音/铃铛 UI 重构、排期表结构 v3 演进，并修复“LLM 多任务只保存一个”与“到点无语音提醒”两个缺陷。

> **状态：全部任务已完成（2026-08-06）。** `flutter analyze` 0 error；`flutter test` 327/327 全绿；实施记录见 PROGRESS.md 阶段 4。

**Architecture:** 数据层沿用 SQLite（`DatabaseHelper` v3 迁移），`Task` 模型扩展 `trigger_type/freq/interval/max_repeats` 等字段；UI 层在现有 `TasksTab/TaskCard` 上重构，语音规划由独立路由改为任务页底部浮层；提醒链路补齐 `ReminderService.init + scheduleAll` 接线，并读取用户提醒设置（静音/震动/语音+音量）。

**Tech Stack:** Flutter 3.44 / sqflite / flutter_local_notifications / flutter_tts / permission_handler

## Global Constraints

- 所有注释、日志、文档使用中文；文件 UTF-8 无 BOM、LF 行尾。
- 核心功能（认证、任务状态流转、冲突检测、提醒调度、对外交互）单元测试 100% 覆盖，非核心 ≥80%。
- 状态收敛后仅 4 个 Tab：全部 / 进行中 / 冲突 / 已完成；移除待办、逾期。
- 所有列表按 `created_at DESC` 排序。
- 冲突任务不进“进行中”；“已完成”只展示不再执行的死任务。
- 保存操作后自动返回（所有保存同理）。
- 不新增第三方依赖；沿用现有 token（温暖平面）。

---

### Task 1: 数据层 v3（模型 + 迁移 + DAO + Store 语义）

**Files:**
- Modify: `lib/models/task.dart`
- Modify: `lib/data/database_helper.dart`
- Modify: `lib/data/daos/task_dao.dart`
- Modify: `lib/services/task_store.dart`
- Test: `test/task_model_test.dart`, `test/task_dao_test.dart`, `test/task_store_test.dart`

**Interfaces:**
- Consumes: 现有 `Task`/`TaskDao`/`TaskStore` API。
- Produces: `TriggerType`、`FreqType` 枚举；`Task.triggerType/freqType/freqInterval/endAt/intervalSeconds/maxRepeats/repeatCount/nextFireTime/prevFireTime`；`Task.isDeadDone`、`Task.nextFireFor(now)`；`TaskDao.listByUser` 按 `created_at DESC`；`TaskStore.all` 同序。

步骤（TDD，每步先写失败测试再实现）：
1. `Task` 模型新增枚举与字段 + `toMap/fromMap` 往返。
2. `DatabaseHelper` v3：`ALTER TABLE tasks ADD COLUMN trigger_type ...` 等 9 列；新增 `user_settings` 表（reminder_mode/vibrate/reminder_volume）；迁移旧行（repeat→trigger_type；`status='missed'`→`'pending'`）。
3. `TaskDao.listByUser` 排序改 `created_at DESC`。
4. `TaskStore`：排序改创建时间降序；删除 `missed` 逻辑；`toggleDone` 对 DELAYED 任务推进 `repeatCount` 并计算 `next_fire_time`；提供 `isDeadDone`（done 且无未来发生）。
5. 全量相关测试通过。

### Task 2: 状态语义与视觉样式

**Files:**
- Modify: `lib/theme/task_status_style.dart`
- Test: `test/task_status_style_test.dart`

步骤：
1. 移除 `overdue/missed` 视觉态；新增 `timer`（倒计时重复）态；`inProgress` 判定排除冲突；`done` 判定改为“死任务”。
2. 筛选口径：全部/进行中/冲突/已完成，计数与列表一致。

### Task 3: 任务卡片与列表页

**Files:**
- Modify: `lib/widgets/task_card.dart`
- Modify: `lib/modules/tasks/tasks_tab.dart`
- Create: `lib/modules/tasks/task_detail_sheet.dart`
- Test: `test/task_card_test.dart`, `test/tasks_tab_test.dart`

步骤：
1. `TaskCard` 统一记录行：状态图标打头、标题单行省略、元信息单行；冲突仅红图标 + “冲突 · 暂不生效”标记；移除卡内冲突操作与复选框；`onTap` 打开详情抽屉。
2. 详情抽屉：可编辑字段（时间/资源/响铃/重复）+ 冲突原因卡（确认覆盖/改时间换资源）+ 单一「完成」；保存后自动返回。
3. `TasksTab`：4 Tab + 计数；问候语读昵称（MainPage 传入）；铃铛/头像按钮接线；长按多选 → 底部「删除(N)/取消」双按钮（移除右上角图标）。

### Task 4: 语音规划同页浮层

**Files:**
- Modify: `lib/modules/tasks/voice_input_screen.dart`
- Modify: `lib/modules/tasks/tasks_tab.dart`（入口改为 `showModalBottomSheet`）
- Test: `test/voice_input_screen_test.dart`

步骤：
1. 改为底部浮层（不跳转新页面）：输入框 + 光标；录音转写插入光标处不覆盖；录音按钮单层环 + 红方块；耳朵 + 音波动效。
2. 排期结果同浮层展示：冲突条目仅红色标记，点条目进详情抽屉。
3. 修复多任务只保存一个：保存循环逐条 try/catch；补 `parseJson` 多任务单测；全流程 widget 测试。

### Task 5: 铃铛提醒设置 + 提醒链路修复

**Files:**
- Modify: `lib/data/database_helper.dart`（Task 1 已建 user_settings）
- Create: `lib/data/daos/settings_dao.dart`
- Modify: `lib/services/reminder_service.dart`
- Modify: `lib/app.dart`、`lib/screens/main_page.dart`、`lib/modules/tasks/tasks_tab.dart`
- Test: `test/reminder_service_test.dart`、新增 `test/settings_dao_test.dart`

步骤：
1. `SettingsDao` + 铃铛浮层（静音/语音互斥、震动独立开关、音量滑杆）持久化。
2. `ReminderService.init` 读取设置：静音不发声（仅通知）、震动开关、语音音量（TTS setVolume）。
3. 补齐接线：登录后 `reminder.init(store)` + `scheduleAll()`；`main.dart`/`App` 注入。

### Task 6: 收尾验证与文档

- `flutter analyze` 0 error；`flutter test` 全绿。
- 更新 `PROGRESS.md`、`docs/smoke-checklist.md`、`FEATURES.md`（状态收敛/排序/语音浮层/铃铛设置/表结构 v3）。
- 提交。

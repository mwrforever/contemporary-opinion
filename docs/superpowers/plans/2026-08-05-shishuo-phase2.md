# 时说 · 阶段 2（语音规划）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans（本仓库沿用阶段 1 的内联 TDD 执行方式）。Steps use checkbox (`- [ ]`)。

**Goal:** 落地「语音规划」完整闭环：录音 → ASR 转写 → LLM/本地 NLP 排期解析 → 逐条冲突检测 → 四态预览 → 确认添加，并把结果反馈接入任务列表。

**Architecture:** 复用现有纯 Dart 语音管线（`AliyunAsrService` / `AliyunScheduleService` / `NlpParser` / `ConflictDetector` / `PromptLoader`），新增「解析结果 → Task」适配层与新的 `VoiceInputScreen`（SQLite TaskStore 版），全部可注入测试。

**Tech Stack:** 沿用阶段 1 锁定栈（record 7.1.1 / http 1.6.0 / permission_handler 13 / Provider）；不新增依赖。

## 全局约束

- 纯移动端；注释/日志/SnackBar 中文；TDD 先写失败测试。
- 语音四态视觉与设计稿一致（冲突红框三操作 / 待定黄框设时间 / 弱提醒黄字 / 已过去红框跳过）。
- 无云端 Key（`AliyunConfig.dashscopeApiKey` 为空）时：**App 不做录音/ASR**，语音页退化为文本输入框——用户手写，或经系统输入法自带语音转文字把话说进输入框；随后走本地 `NlpParser` 解析。不调用设备端 speech_to_text（FEATURES 已移除）。
- `RECORD_AUDIO` 权限首次请求（permission_handler 13）；拒绝时引导设置。
- 核心链路（映射/冲突四态/权限）测试覆盖目标 100%；UI ≥80%。

---

## 文件结构

```
lib/
  services/voice_task_adapter.dart   新增：ScheduledTask/ParsedTask → Task（纯函数）
  modules/tasks/voice_input_screen.dart 新增：录音/转写/解析/四态预览/确认添加
  modules/tasks/task_feedback_card.dart 新增（重建轻量版）：{added, conflict, skipped} 结果提示
  modules/tasks/tasks_tab.dart      修改：Speed Dial 语音 → VoiceInputScreen；返回结果提示
  models/task.dart                  修改：新增 note 字段（toMap/fromMap/round-trip）
  main.dart / app.dart              修改：启动加载 PromptLoader.loadAll()
test/
  voice_task_adapter_test.dart      新增
  voice_input_screen_test.dart      新增（fake ASR/排期/NLP）
  task_model_test.dart              修改（note 字段）
  tasks_tab_test.dart               修改（语音入口 + 结果提示）
```

---

## Task P2-1: Task 模型补充 note 字段

**Files:** `lib/models/task.dart`、`test/task_model_test.dart`

**Interfaces:** `Task` 新增 `String? note`；`toMap`/`fromMap` 读写 `note` 列。

- [ ] 测试：round-trip 携带 note；toMap 含 `note`。
- [ ] 实现并全量回归（老数据 note=null 兼容）。
- [ ] Commit: `feat: Task 模型补充 note 字段`

---

## Task P2-2: 语音解析结果适配器

**Files:** `lib/services/voice_task_adapter.dart`、`test/voice_task_adapter_test.dart`

**Interfaces:**
- `Task taskFromScheduled(ScheduledTask s, {required String titleFallback})`：datetime 缺失→scheduledTime=null（进入 undated 流程）；倒计时字段（若有）折算为「now+秒」绝对时间并保留 countdownMinutes/Seconds。
- `Task taskFromParsed(ParsedTask p, {required DateTime now})`：同上，负责 NlpParser 离线结果。
- 输出统一 `Task`（id 由调用方注入 UUID；notificationId 由调用方生成）。

- [ ] 测试：绝对时间映射 / 倒计时折算（含跨日）/ repeat+weekdays 映射 / resource/duration/ring / note / datetime 缺失 → undated 前置。
- [ ] 实现。
- [ ] Commit: `feat: 语音解析结果→Task 适配器`

---

## Task P2-3: 语音规划页（录音 + 转写 + 解析 + 四态预览）

**Files:** `lib/modules/tasks/voice_input_screen.dart`、`test/voice_input_screen_test.dart`

**Interfaces:**
```dart
class VoiceInputScreen extends StatefulWidget {
  const VoiceInputScreen({super.key, required this.store, required this.reminder,
    this.asr, this.schedule, this.capture, this.parser});
}
/// 返回: VoicePlanResult { int added; int conflict; int skipped; }
```
- 依赖全部可注入（`AliyunAsrService?` / `AliyunScheduleService?` / `AudioCapture?` / `NlpParser` 静态）；无 key 时隐藏录音、显示文本输入框。
- 流程：录音（AudioCapture.startStream → stop 收 PCM）→ `asr.transcribe` → `schedule.schedule`（失败或空结果回退 `NlpParser.parse`）→ 每候选 `ConflictDetector.detect` + `applyDecision` 得四态。
- 四态卡：冲突（红框 + 确认覆盖/改时间/换资源）/ 待定（黄框 + 设时间）/ 弱提醒（黄字正常生效）/ 已过去（红框 + 保存跳过）。
  - 「改时间 / 换资源 / 设时间」= 打开阶段 1 的 `AddTaskScreen` 编辑表单手动修改（**非语音操作**）。
- 底部：`添加 N 条 · 跳过 M 条` + 确认添加（已跳过的不入库；冲突待处理需用户先三选一或保持未添加）。

- [ ] 测试：四态判定（用注入的假 schedule/parser 返回固定候选）；离线路径为文本输入框（用户手写或系统输入法语音转文字）走 NLP；无 key 不显示录音按钮；确认添加计数与 store 落库；跳过计数。
- [ ] 实现（UI 按设计稿方向 A）。
- [ ] Commit: `feat: 语音规划页（录音/转写/排期/四态预览）`

---

## Task P2-4: 结果反馈卡 + TasksTab 接入

**Files:** `lib/modules/tasks/task_feedback_card.dart`、`lib/modules/tasks/tasks_tab.dart`、`test/tasks_tab_test.dart`

**Interfaces:**
- `TaskFeedbackCard({required VoicePlanResult result})`：一行摘要（如「已添加 2 条 · 1 条冲突待处理 · 1 条跳过」），可手动关闭。
- `TasksTab._goVoice()` 改为 push `VoiceInputScreen`，`pop` 返回结果后经底部提示展示。

- [ ] 测试：返回结果后出现摘要；关闭按钮移除。
- [ ] 实现；Speed Dial「语音规划」不再弹占位 SnackBar。
- [ ] Commit: `feat: 语音规划结果反馈与任务列表接入`

---

## Task P2-5: 启动加载提示词 + 权限收尾

**Files:** `lib/main.dart` / `lib/app.dart`、`test/app_routing_test.dart`

- [ ] App 启动（AuthGate 之前）`await PromptLoader.loadAll()`（幂等，失败静默）。
- [ ] 语音页首次进入请求 `RECORD_AUDIO`（permission_handler 13，`Permission.microphone`），拒绝引导设置；widget 测试注入 mock 权限结果。
- [ ] 全量 `flutter analyze` 0 error + `flutter test` 全绿。
- [ ] Commit: `feat: 启动加载提示词并完成麦克风权限流程`

---

## Self-Review

**规格覆盖（FEATURES 三、3.2B 语音规划）**：录音→ASR→排期→冲突预览→确认添加 ✓（P2-3）；离线 NLP 兜底 ✓（P2-2/P2-3）；四态视觉 ✓（P2-3）；返回 {added, conflict, skipped} 反馈 ✓（P2-4）；提示词 YAML 两份 ✓（P2-5 加载既有资产）；`RECORD_AUDIO` 权限 ✓（P2-5）。
**类型一致性**：`VoicePlanResult{added, conflict, skipped}` 在 P2-3/P2-4 间一致；适配器输出统一 `Task` 供 TaskStore 使用。
**占位符**：无 TBD；语音「改时间/换资源」复用阶段 1 的 AddTaskScreen（editTask 模式）。

---

## 阶段 3/4 预告（独立计划）

- 阶段 3 记事本：SQLite v2 迁移六表 + Hub + 六子功能 + 自绘报表。
- 阶段 4 上架：应用图标（品牌文档方案）、商店长描述、隐私说明、厂商保活矩阵、可选 i18n。

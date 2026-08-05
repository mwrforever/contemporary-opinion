# 时说 · 阶段 3（记事本）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans（沿用阶段 1/2 内联 TDD 执行方式）。Steps use checkbox (`- [ ]`)。

**Goal:** 记事本六大子功能（购物/收支/读书/旅游/学习/菜谱）从 Hive 迁到 SQLite，落地 2 列 Hub、各子功能表单/详情、自绘报表，并把阶段 2 遗留的 hive 依赖彻底移除。

**Architecture:** 沿用三层：`lib/data/daos`（每模块一个 DAO，user_id 隔离）→ `NotebookStore`（Provider，对外 API 与旧版一致，内部换 SQLite）→ 新 Hub/详情页（复用 `notebook_shared.dart` 组件与 `notebook_report.dart` 报表）。

**Tech Stack:** 沿用阶段 1 锁定栈（sqflite 2.4.3 / provider 6.1.5）；不新增依赖。

## 全局约束

- 纯移动端；注释/日志中文；TDD 先写失败测试；核心链路（DAO/迁移/报表聚合）100% 覆盖。
- 全部业务表带 `user_id`；嵌套结构（旅游交通/计费、菜谱配料/步骤）按 FEATURES 4.1 以 JSON 列存储。
- 旧 Hive 记事本数据尽力迁移（沿用 Task 9 的冻结适配器模式），迁移后移除 hive_ce / hive_ce_flutter 过渡依赖。
- 报表自绘柱状图保留现有算法（`buildStatsBuckets`/6 桶），仅接线不重写。

---

## 文件结构

```
lib/
  data/database_helper.dart        修改：v2 迁移新增 10 张记事本表
  data/daos/notebook_daos.dart     新增：六模块 DAO（或分文件）
  services/notebook_store.dart     重写：SQLite 实现（保持公开 API）
  services/legacy_notebook_migration.dart 新增：旧 Hive 记事本数据迁移
  modules/notebook/notebook_tab.dart  新增：2 列 Hub（设计稿）
  modules/notebook/screens/…          新增：六子功能详情页（表单/列表/编辑）
  modules/notebook/widgets/…          复用 notebook_shared / notebook_report
test/
  database_helper_test.dart        修改：v2 建表断言
  notebook_*_dao_test.dart         新增
  notebook_store_test.dart         重写为 SQLite
  legacy_notebook_migration_test.dart 新增
  notebook_tab_test.dart           新增
  notebook_report_test.dart        保留（算法回归）
```

---

## Task P3-1: SQLite v2 迁移（10 张表）

**Files:** `lib/data/database_helper.dart`、`test/database_helper_test.dart`

**Interfaces:** `DatabaseHelper._dbVersion = 2`；`_onUpgrade` 从 v1 建记事本表；表名与 FEATURES 4.1 一致：
`shopping_carts / shopping_items / ledger / reading / trips / trip_days / trip_checkpoints / courses / study_records / recipes`，均含 `user_id` 外键；嵌套结构用 `TEXT` JSON 列。

- [ ] 测试：v2 建表齐全（先 v1 建库再升级或直接 v2 建全表）；外键/唯一约束抽查。
- [ ] 实现 `_onUpgrade`；保持 v1 表不变。
- [ ] Commit: `feat: SQLite v2 记事本十表迁移`

---

## Task P3-2: 六模块 DAO（分组 2 个提交）

**Files:** `lib/data/daos/notebook_*.dart`、`test/notebook_*_dao_test.dart`

**Interfaces:** 每 DAO 提供 `insert/update/delete/listByUser(int userId)`；旅游含嵌套（trips→days→checkpoints）级联读写；JSON 列用模型既有 `toJson/fromJson`。

- [ ] 提交 A：购物（cart+item 聚合/孤儿回收）+ 收支 + 读书 DAO + 测试。
- [ ] 提交 B：旅游（三层级联）+ 学习（课程+记录）+ 菜谱 DAO + 测试。

---

## Task P3-3: NotebookStore 换 SQLite（保持 API）

**Files:** `lib/services/notebook_store.dart`、`test/notebook_store_test.dart`

**Interfaces:** 保留现有公开方法（`shopping/ledger/reading/trips/recipes/courses` getter + `add/update/delete`），`init()` 改为从各 DAO 加载；`user_id` 由构造注入（`NotebookStore({required int userId, ...})`）。

- [ ] 测试：init 加载、增删改查、user_id 隔离。
- [ ] 实现并删除 Hive 引用。
- [ ] Commit: `refactor: NotebookStore 迁移 SQLite`

---

## Task P3-4: 旧 Hive 记事本数据迁移

**Files:** `lib/services/legacy_notebook_migration.dart`、`test/legacy_notebook_migration_test.dart`

**Interfaces:** `Future<int> migrateLegacyNotebook(int userId)`：读取旧 `notebook_*` boxes（沿用既有模型序列化），写入 SQLite；幂等标记；失败静默。

- [ ] 测试：购物/账本/读书各迁 1 条 → 表内有值且归属 user_id；空库幂等。
- [ ] 实现；完成后从 pubspec 移除 `hive_ce`/`hive_ce_flutter` 过渡依赖。
- [ ] Commit: `feat: 旧记事本 Hive 数据迁移并移除过渡依赖`

---

## Task P3-5: 记事本 Hub（2 列网格）

**Files:** `lib/modules/notebook/notebook_tab.dart`、`test/notebook_tab_test.dart`

**Interfaces:** `NotebookTab({required NotebookStore store})`；2 列网格六卡（图标 + 名称 + 条目数速览，语义色块）；点击进入对应详情页。

- [ ] 测试：六卡渲染、条目数正确、点击导航。
- [ ] MainPage「记事本」Tab 接入真实 store（userId 注入）。
- [ ] Commit: `feat: 记事本 Hub 2 列网格`

---

## Task P3-6: 六子功能详情页（分组 2 个提交）

**Files:** `lib/modules/notebook/screens/*.dart`、对应测试

**Interfaces:** 每页：列表（复用 `notebook_shared` 表单组件）+ 新增/编辑/删除 + 金额/评分数字键盘 + 日期 `showDatePicker`；旅游页含行程日/打卡点嵌套编辑。

- [ ] 提交 A：购物（含报表入口）+ 收支（含报表入口）+ 读书。
- [ ] 提交 B：旅游 + 学习 + 菜谱。
- [ ] 每页至少一条增删改 widget 测试。

---

## Task P3-7: 报表接线与集成验证

**Files:** `lib/modules/notebook/widgets/notebook_report.dart`（如需微调）、`test/notebook_report_test.dart`（保留）

- [ ] 购物消费趋势 / 收支报表页接入 store 数据与 `ReportScreen`（日/月/年、6 桶堆叠）。
- [ ] `flutter analyze` 0 error；全量 `flutter test` 全绿；debug APK 构建。
- [ ] Commit: `feat: 记事本报表接线与阶段 3 集成验证`

---

## Self-Review

**规格覆盖（FEATURES 四）**：六表结构 ✓（P3-1/P3-2）；六子功能录入/编辑/删除 ✓（P3-6）；Hub 2 列网格 ✓（P3-5）；报表日/月/年 + 收支堆叠/购物趋势 ✓（P3-7）；旅游嵌套与 JSON 列 ✓（P3-2）；user_id 隔离 ✓（P3-2/P3-3）；旧数据迁移 ✓（P3-4）；hive 依赖移除 ✓（P3-4）。
**类型一致性**：`NotebookStore` 公开 API 与旧版一致，避免 Hub/详情页大改；DAO 统一 `insert/update/delete/listByUser`。
**占位符**：无 TBD；报表算法复用不重写。

---

## 阶段 4 预告（独立计划）

应用图标（品牌文档方案）、商店长描述、隐私说明、Android 厂商保活矩阵、可选 i18n。

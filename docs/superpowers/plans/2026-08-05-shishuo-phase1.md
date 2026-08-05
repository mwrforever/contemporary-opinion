# 时说 · 阶段 1（核心闭环）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有 Hive/Web 旧架构重构为 FEATURES.md 新规格的「本地 SQLite + 本地账户 + 纯移动端」架构，交付可运行的**登录/注册 + 路由守卫 + 任务手动录入（含冲突检测）+ 任务列表 + 基础提醒 + 设计 Token 落地**闭环，并删除全部 Web/旧存储死代码与失效测试。

**Architecture:** 三层：`lib/data`（sqflite 单例 DatabaseHelper + DAO + 纯 Dart 模型）→ `lib/services`（Auth/Conflict/Reminder/Backup 等业务服务，可单测）→ `lib/screens|modules`（Provider 状态 + 页面，视觉按 `docs/superpowers/specs/2026-08-05-shishuo-ui-design.md` 落地）。App 启动经路由守卫读 session 决定进登录页或任务列表。

**Tech Stack:** Flutter 3.44.8 stable / Dart 3.12.2（本机已装）；sqflite + Provider + flutter_local_notifications + audioplayers + flutter_tts + record + permission_handler + crypto + share_plus/file_picker；详见「技术栈锁定表」。**先跑通 `flutter pub get` + `flutter analyze` + `flutter test` 再开始改业务代码。**

## 全局约束（每个任务默认遵守）

- Flutter 3.44.8 / Dart 3.12.2；`pubspec.yaml` 的 `environment.sdk` 保持 `^3.12.2`。
- 纯移动端（Android 优先、iOS 待补）；锁定竖屏；SafeArea + 触控目标 ≥48pt。
- 依赖只使用「技术栈锁定表」中的最新稳定版；**禁止**引入 Hive/Web/未维护包。
- 所有注释、日志、SnackBar 文案、commit message 使用中文；禁止打印敏感信息。
- TDD：先写失败测试 → 运行确认失败 → 最小实现 → 运行确认通过 → 提交。
- 核心路径（认证/权限/冲突检测/提醒调度/数据持久化）单元测试覆盖率目标 100%；其余 ≥80%。
- 因本次改动失效的旧测试直接删除，不留过渡。
- 提交粒度：每个任务一个 commit，只 add 本任务文件。
- **本机环境限制**：Android SDK 未安装（`D:\code\android-sdk` 不存在）、无 Visual Studio、maven.google.com 网络超时——本机只能执行 `flutter analyze` / `flutter test`；APK 构建需先安装 SDK 并恢复网络。Android 平台配置（desugaring/权限）仍在本计划完成，以便有 SDK 的机器直接构建。

---

## 技术栈锁定表（2026-08-05 查证 pub.dev）

| 用途 | 包 | 锁定版本 | 选择理由 / 维护状态 |
|------|----|---------|--------------------|
| 本地数据库 | sqflite | 2.4.3 | FEATURES 指定；2026-06 活跃发布；移动端 SQLite 事实标准 |
| 库测试环境 | sqflite_common_ffi | 2.4.2 | 纯 Dart/CI 跑 DAO 测试（dev 依赖） |
| 状态管理 | provider | 6.1.5+1 | FEATURES 指定；生态成熟、低变更 |
| 精确通知 | flutter_local_notifications | 22.2.0 | 2026-07 最新；`exactAllowWhileIdle` 系统级调度；需 desugaring |
| 时区 | timezone | 0.11.1 | FEATURES 指定（锁 Asia/Shanghai） |
| 响铃 | audioplayers | 6.8.1 | FEATURES 指定；2026-06 活跃；**替换** just_audio 0.10.6（活跃度更高） |
| 音频会话 | audio_session | 0.2.4 | 配合响铃 alarm 会话 |
| 中文播报 | flutter_tts | 4.2.5 | 2026-01 发布，继续维护 |
| 录音 PCM | record | 7.1.1 | 2026-06 活跃；与 Dart 3.12 对齐（sdk ^3.12.0） |
| 头像选择 | image_picker | 1.2.3 | 官方维护（flutter.dev 组织） |
| 权限 | permission_handler | 13.0.0 | 2026-07 最新主版本；注意 12→13 破坏性变更，代码按 13 写 |
| 路径 | path_provider | 2.1.6 | 官方维护 |
| HTTP | http | 1.6.0 | 官方轻量；仅 DashScope 1–2 个端点，不引 dio |
| 密码哈希 | crypto | 3.0.7 | Dart 官方；PBKDF2-HMAC-SHA256 自实现（小函数 + 单测） |
| 备份导出 | share_plus | 13.3.0 | 2026-07 活跃 |
| 备份导入 | file_picker | 11.0.3 | 2026-07 活跃 |
| 版本信息 | package_info_plus | 10.2.1 | 关于页 |
| 系统设置跳转 | url_launcher | 6.3.2 | 权限被拒引导 |
| 工具 | intl / uuid / yaml | 0.20.3 / 4.6.0 / 3.1.3 | 官方/社区活跃 |

**移除（不再使用/未维护）**：`hive_ce`/`hive_ce_flutter`（→ sqflite；仅迁移器测试临时用 dev 依赖）、`speech_to_text`（语音走 Aliyun ASR，规格已改）、`record_web`/`web`（纯移动端）、`just_audio`（→ audioplayers）、`flutter_ringtone_player`（已弃，确认不在 pubspec）。

---

## 文件结构规划

```
lib/
  main.dart                      修改：启动读 session 做路由守卫
  app.dart                      新增：MaterialApp + 主题 + 路由表
  app/tab_shell.dart            修改：主框架（任务/记事本/我的）
  config/aliyun_config.dart     修改：只保留 ASR/Schedule 端点与 Key 读取
  data/
    database_helper.dart        新增：sqflite 单例（建表/onUpgrade）
    models/user.dart            新增：users 表模型
    models/session.dart         新增：session 单行模型
    models/task.dart            修改：去 Hive 注解，toMap/fromMap
    daos/user_dao.dart          新增
    daos/session_dao.dart       新增
    daos/task_dao.dart          新增
  services/
    password_hasher.dart        新增：PBKDF2-HMAC-SHA256
    auth_service.dart           新增：注册/登录/登出/当前用户
    backup_service.dart         新增：JSON 导出/导入
    legacy_migration.dart       新增：旧 Hive → SQLite 尽力迁移
    reminder_service.dart       修改：通知 22 + audioplayers 响铃 + TTS
    audio_service.dart          修改：只保留 IO 实现
    task_store.dart             修改：Provider → SQLite
    settings_service.dart       修改：读用户表默认响铃
  screens/
    login_page.dart             新增（视觉按设计稿）
    register_page.dart          新增
    splash_screen.dart          修改：仅未登录首启品牌页
  theme/app_theme.dart          修改：设计 Token 落地
  modules/tasks/...             修改：列表/添加页视觉升级（手动链路）
  widgets/...                   修改：任务卡片四态、Speed Dial 视觉
test/                            同步删除旧测试、新增对应用例
android/                         修改：desugaring、Manifest 权限
```

---

## Task 1: 依赖重排与 Android 平台配置

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Test: 无（验证 = `flutter pub get` / `flutter analyze` / `flutter test`）

**Interfaces:**
- Consumes: 现有 pubspec 全量。
- Produces: 可解析的新依赖集（Task 2+ 全部建立在其上）。

- [ ] **Step 1: 编辑 pubspec.yaml**

```yaml
environment:
  sdk: ^3.12.2

dependencies:
  flutter: { sdk: flutter }
  provider: ^6.1.5+1
  sqflite: ^2.4.3
  flutter_local_notifications: ^22.2.0
  timezone: ^0.11.1
  audioplayers: ^6.8.1
  audio_session: ^0.2.4
  flutter_tts: ^4.2.5
  record: ^7.1.1
  image_picker: ^1.2.3
  permission_handler: ^13.0.0
  path_provider: ^2.1.6
  http: ^1.6.0
  crypto: ^3.0.7
  share_plus: ^13.3.0
  file_picker: ^11.0.3
  package_info_plus: ^10.2.1
  url_launcher: ^6.3.2
  intl: ^0.20.3
  uuid: ^4.6.0
  yaml: ^3.1.3

dev_dependencies:
  flutter_test: { sdk: flutter }
  flutter_lints: ^6.0.0
  sqflite_common_ffi: ^2.4.2
  hive_ce: ^2.19.0   # 仅迁移器测试用，Task 9 完成后删除
```

删除：`hive_ce_flutter`、`speech_to_text`、`record_web`、`web`、`just_audio`、`flutter_ringtone_player`。

- [ ] **Step 2: Android 构建配置（desugaring + 权限）**

`android/app/build.gradle.kts`：
```kotlin
android {
  compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
  }
}
dependencies {
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```
`AndroidManifest.xml` 增加：
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.VIBRATE"/>
```

- [ ] **Step 3: 解析依赖**
Run: `flutter pub get`
Expected: `Got dependencies!`，无版本冲突（若冲突，按锁定表微调 caret 版本并记录原因）。

- [ ] **Step 4: 静态检查与基线测试**
Run: `flutter analyze`
Expected: 0 error（存量 warning 记录到 PROGRESS.md，不改动无关代码）。
Run: `flutter test`
Expected: 记录当前通过/失败清单，作为重构基线（失败项必须属于「将被 Task 10 删除的旧测试」）。

- [ ] **Step 5: Commit**
```bash
git add pubspec.yaml pubspec.lock android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml
git commit -m "chore: 重排依赖至最新稳定版并配置 Android desugaring 与权限"
```

---

## Task 2: DatabaseHelper（SQLite 单例 + 建表）

**Files:**
- Create: `lib/data/database_helper.dart`
- Test: `test/data/database_helper_test.dart`

**Interfaces:**
- Consumes: sqflite、path_provider。
- Produces: `DatabaseHelper.instance.database → Future<Database>`；`Future<void> close()`；schema 版本 1（users/session/tasks）。

- [ ] **Step 1: 写失败测试**（核心断言：三张表存在、users.username 唯一、tasks 有 user_id）

```dart
// test/data/database_helper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('建库后创建 users/session/tasks 三张表', () async {
    DatabaseHelper.setFactoryForTest(databaseFactory);
    final db = await DatabaseHelper.instance.database;
    final tables = await db.query('sqlite_master',
        where: "type='table' AND name IN ('users','session','tasks')");
    expect(tables.length, 3);
    final cols = await db.rawQuery("PRAGMA table_info(tasks)");
    expect(cols.map((c) => c['name']), containsAll(['user_id', 'title', 'conflict_state', 'effective']));
    await DatabaseHelper.instance.close();
  });
}
```

- [ ] **Step 2: 运行确认失败**
Run: `flutter test test/data/database_helper_test.dart`
Expected: FAIL（找不到 `DatabaseHelper`）。

- [ ] **Step 3: 实现**

```dart
// lib/data/database_helper.dart
/// 本地 SQLite 数据库单例：统一建表、迁移与读写入口。
/// 依赖 sqflite；业务表均携带 user_id 归属当前登录用户。
/// 注意：非线程安全，App 内单例使用，禁止并发 open/close。
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();
  static DatabaseFactory _factoryOverride = databaseFactory;
  static void setFactoryForTest(DatabaseFactory f) => _factoryOverride = f;

  static const _dbName = 'daily_planner.db';
  static const _dbVersion = 1;
  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    return _factoryOverride.openDatabase(
      _dbName,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        nickname TEXT,
        avatar_path TEXT,
        default_ring_seconds INTEGER,
        created_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE session(
        id INTEGER PRIMARY KEY CHECK(id = 1),
        user_id INTEGER,
        is_logged_in INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        scheduled_time TEXT,
        countdown_minutes INTEGER,
        countdown_seconds INTEGER,
        repeat TEXT NOT NULL DEFAULT 'none',
        custom_weekdays TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        source TEXT NOT NULL DEFAULT 'manual',
        resource TEXT,
        duration_minutes INTEGER NOT NULL DEFAULT 0,
        ring_seconds INTEGER,
        conflict_state TEXT NOT NULL DEFAULT 'none',
        effective INTEGER NOT NULL DEFAULT 1,
        notification_id INTEGER,
        completed_at TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('CREATE INDEX idx_tasks_user ON tasks(user_id, status)');
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // 预留：后续记事本六表在 v2 迁移中新增
  }

  Future<void> close() async { await _db?.close(); _db = null; }
}
```

- [ ] **Step 4: 运行确认通过**
Run: `flutter test test/data/database_helper_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**
```bash
git add lib/data/database_helper.dart test/data/database_helper_test.dart
git commit -m "feat: 新增 SQLite 单例与 users/session/tasks 建表"
```

---

## Task 3: PasswordHasher（PBKDF2-HMAC-SHA256）

**Files:**
- Create: `lib/services/password_hasher.dart`
- Test: `test/password_hasher_test.dart`

**Interfaces:**
- Produces:
  - `String generateSalt({int length = 16})` → base64 随机盐；
  - `String hash(String password, {String? salt, int iterations = 60000})` → `pbkdf2$iterations$saltB64$hashB64`；
  - `bool verify(String password, String stored)` → 解析 stored 重算比对（恒定时间比较）。

- [ ] **Step 1: 写失败测试**

```dart
test('同密码同盐哈希一致、盐不同哈希不同、verify 校验正确', () {
  final h1 = hash('mima123456', salt: 'fixed-salt-0123456789');
  final h2 = hash('mima123456', salt: 'fixed-salt-0123456789');
  final h3 = hash('mima123456');
  expect(h1, h2);
  expect(h1, isNot(h3));
  expect(verify('mima123456', h1), isTrue);
  expect(verify('wrong', h1), isFalse);
});
```

- [ ] **Step 2: 运行确认失败** → `flutter test test/password_hasher_test.dart` FAIL（找不到 hash）。

- [ ] **Step 3: 实现**（HMAC 来自 `package:crypto`）

```dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 密码哈希（本地账户生产级最小实现）。
/// 输出格式：pbkdf2$迭代次数$盐base64$摘要base64；verify 恒定时间比较。
String generateSalt({int length = 16}) {
  final rng = Random.secure();
  final bytes = List<int>.generate(length, (_) => rng.nextInt(256));
  return base64Encode(bytes);
}

String hash(String password, {String? salt, int iterations = 60000}) {
  final s = salt ?? generateSalt();
  final hmac = Hmac(sha256, utf8.encode(password));
  var u = hmac.convert(base64Decode(s)).bytes;
  var result = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) result[j] ^= u[j];
  }
  return 'pbkdf2\$$iterations\$$s\$${base64Encode(result)}';
}

bool verify(String password, String stored) {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations <= 0) return false;
  return _constEq(hash(password, salt: parts[2], iterations: iterations), stored);
}

bool _constEq(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  return diff == 0;
}
```

- [ ] **Step 4: 运行确认通过** → PASS。
- [ ] **Step 5: Commit** → `feat: 新增 PBKDF2-HMAC-SHA256 密码哈希`

---

## Task 4: UserDao + SessionDao

**Files:**
- Create: `lib/data/models/user.dart`、`lib/data/models/session.dart`
- Create: `lib/data/daos/user_dao.dart`、`lib/data/daos/session_dao.dart`
- Test: `test/data/user_dao_test.dart`、`test/data/session_dao_test.dart`

**Interfaces:**
- Produces:
  - `class User { int? id; String username; String passwordHash; String? nickname; String? avatarPath; int? defaultRingSeconds; DateTime createdAt; Map<String,dynamic> toMap(); factory User.fromMap(...); }`
  - `class Session { int? userId; bool isLoggedIn; }`
  - `UserDao({Database? db})`：`Future<int> insert(User)`、`Future<User?> findByUsername(String)`、`Future<User?> findById(int)`、`Future<void> update(User)`；
  - `SessionDao({Database? db})`：`Future<void> write(int userId, bool isLoggedIn)`（恒 id=1 upsert）、`Future<Session?> read()`。

- [ ] **Step 1-2:** 用 sqflite_common_ffi 建 in-memory 库（复用 Task 2 的 DatabaseHelper），先写测试：注册插入后 findByUsername 命中、update 生效、session write/read 单行覆盖。
Run: FAIL（类不存在）。
- [ ] **Step 3: 实现**（upsert 用 `db.insert('session', {'id':1, ...}, conflictAlgorithm: ConflictAlgorithm.replace)`；读 session 返回 `is_logged_in == 1`）。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: 新增用户与会话 DAO`

---

## Task 5: AuthService（注册/登录/登出）

**Files:**
- Create: `lib/services/auth_service.dart`
- Test: `test/auth_service_test.dart`

**Interfaces:**
- Consumes: UserDao/SessionDao/PasswordHasher/DatabaseHelper。
- Produces:
  - `class AuthResult { bool ok; String? error; User? user; }`
  - `Future<AuthResult> register({required String username, required String password, String? nickname})`；
  - `Future<AuthResult> login(String username, String password)`；
  - `Future<void> logout()`；
  - `Future<User?> currentUser()`。

- [ ] **Step 1-2:** 测试：注册成功写 session 并返回用户；用户名重复返回中文错误 `用户名已被占用`；密码 <6 位返回 `密码至少 6 位`；登录成功/密码错误 `用户名或密码错误`；logout 后 currentUser 为 null。
Run: FAIL。
- [ ] **Step 3: 实现**（register 先 `findByUsername` 判重；login 用 verify；成功后 `sessionDao.write(user.id!, true)`；logout `sessionDao.write(0, false)`；`currentUser` 读 session 再 findById）。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: 新增本地账户注册/登录/登出服务`

---

## Task 6: 路由守卫与 Splash 改造

**Files:**
- Create: `lib/app.dart`
- Modify: `lib/main.dart`
- Modify: `lib/screens/splash_screen.dart`
- Test: `test/app_routing_test.dart`

**Interfaces:**
- Consumes: AuthService.currentUser / session。
- Produces: `App` widget：`MaterialApp(theme: buildAppTheme(), darkTheme: buildAppTheme(Brightness.dark), home: FutureBuilder<AuthGate>)`；`AuthGate` 读 session → 已登录 `MainPage`，未登录 `SplashScreen`（1.2s 后 `LoginPage`）。

- [ ] **Step 1-2:** widget 测试：session 已登录 → pump App → 出现「任务」Tab；未登录 → 出现「时说」品牌后跳登录页；登出 → 回登录页。
Run: FAIL。
- [ ] **Step 3: 实现**（main.dart 仅 `runApp(const App())`；Splash 保留 FadeIn 品牌，`Future.delayed(1200ms)` pushReplacement 登录页；`AuthGate` 用 FutureBuilder 处理加载态）。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: 路由守卫：已登录直达任务列表，未登录品牌页后进登录`

---

## Task 7: 登录/注册页 UI（按设计稿）

**Files:**
- Create: `lib/screens/login_page.dart`、`lib/screens/register_page.dart`
- Test: `test/login_page_test.dart`、`test/register_page_test.dart`

**Interfaces:**
- Consumes: AuthService、`buildAppTheme()`。
- Produces: 两个可 push 页面；错误经 SnackBar 就近提示；密码框 `obscureText` 显隐切换；按钮高度 52、触控 ≥48。

- [ ] **Step 1-2:** widget 测试：空提交提示；密码显隐切换；注册页二次密码不一致提示 `两次输入的密码不一致`；成功导航到 MainPage。
Run: FAIL。
- [ ] **Step 3: 实现**（视觉：青绿主按钮、卡片圆角 20、系统字体栈、SafeArea；`Form` + `GlobalKey<FormState>` 校验）。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: 登录/注册页按设计稿落地`

---

## Task 8: 设计 Token 落地 app_theme.dart

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Test: `test/app_theme_test.dart`

**Interfaces:**
- Produces: `ThemeData buildAppTheme([Brightness brightness = Brightness.light])`；token 精确值：accent `#0E8C7F`、按钮色 `#0A7368`、danger `#C0492F`、warn `#C9782B`、ok `#3F9D6B`、浅背景 `#F6F7F4`、深背景 `#101315`、深表面 `#1A1D20`；圆角 20/14/12；`TextTheme` 字号层级 20/800、16/600、14/400、12/400。

- [ ] **Step 1-2:** 测试断言：light/dark 两套 ColorScheme 的 primary/error/surface 精确等于 token；FilledButton 高度主题化 ≥48；卡片 radius 20。
Run: FAIL。
- [ ] **Step 3: 实现**：`ColorScheme.fromSeed(seedColor: accent)` 后显式覆盖字段（fromSeed 会漂色，必须显式赋值保证锁定色值）；`FilledButtonThemeData`、`InputDecorationTheme`、`CardThemeData`、`NavigationBarThemeData`、`ChipThemeData`、`SegmentedButtonThemeData` 一次性收敛。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: 设计 Token 落地 app_theme（浅深自适应）`

---

## Task 9: 旧 Hive → SQLite 尽力迁移器

**Files:**
- Create: `lib/services/legacy_migration.dart`
- Test: `test/legacy_migration_test.dart`（dev 依赖 hive_ce，用 `Hive.init(tempDir)` + 写入旧格式 box 后验证迁移）

**Interfaces:**
- Produces: `Future<bool> migrateLegacyData(Database db)`：检测 `Hive.box('tasks')` / `'notebook'` 存在 → 逐条写入 system 用户（user_id=1）名下 SQLite → 标记 `legacy_migrated`；无旧数据返回 true（幂等）。

- [ ] **Step 1-2:** 测试：空 Hive 迁移后 tasks 表为空且标记完成；有 1 条旧任务（Hive map 格式）迁移后 SQLite 出现同标题任务且 user_id=1。
Run: FAIL。
- [ ] **Step 3: 实现**：映射旧字段到 Task.toMap（缺失字段用默认值）；任何单条解析失败不中断，记 warn 日志继续。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: 旧 Hive 数据尽力迁移至 SQLite 并移除 hive_ce dev 依赖`

---

## Task 10: 删除 Web/旧存储死代码与失效测试

**Files:**
- Delete: `lib/services/audio_capture_web.dart`、`lib/services/audio_service_web.dart`、`lib/services/notification_service_web.dart`、`lib/services/speech_service.dart`、`lib/services/notebook_voice_service.dart`、`lib/utils/`（逐个确认无引用后删）
- Delete: `web/` 目录
- Delete tests: `test/web_adapt_test.dart`、`test/task_adapter_legacy_test.dart`、`test/task_adapter_test.dart`（若 task_adapter 一并废弃）、`test/notebook_voice*`、`test/aliyun_asr*`（语音服务阶段 2 重写，先删旧测）
- Modify: `lib/services/audio_service.dart`、`lib/services/notification_service.dart`（只留 IO 抽象，删 web 分支）
- Test: 验证 = `flutter analyze` 0 error + `flutter test` 全绿

- [ ] **Step 1:** 用 `flutter analyze` 找出引用链，先改 abstraction 再删实现，避免悬空引用。
- [ ] **Step 2:** 删除文件与 `web/` 目录；pubspec.yaml 确认已无 `record_web/web/speech_to_text`。
- [ ] **Step 3:** `flutter analyze` → 0 error；`flutter test` → 全绿。
- [ ] **Step 4: Commit** → `refactor: 清理 Web/旧存储死代码与失效测试`

---

## Task 11: Task 模型适配 SQLite + TaskDao

**Files:**
- Modify: `lib/models/task.dart`
- Create: `lib/data/daos/task_dao.dart`
- Test: `test/task_dao_test.dart`、`test/task_model_test.dart`

**Interfaces:**
- Produces（FEATURES 3.1 全字段；`custom_weekdays` 存 JSON 字符串，fromMap 解析）：
  - `Map<String,dynamic> toMap()` / `factory Task.fromMap(Map)`（含 conflict_state、effective、notification_id、completed_at、source）；
  - `TaskDao({Database? db})`：`insert` / `update` / `delete` / `findById` / `listByUser(int userId, {String? statusFilter, bool? effectiveOnly})`。

- [ ] **Step 1-2:** 测试：round-trip 全字段；按 user_id 隔离（两个用户互不可见）；status 过滤；删除生效。
Run: FAIL。
- [ ] **Step 3: 实现**：移除 `@HiveType` 注解与 adapter；字段名 snake_case 映射；custom_weekdays 用 jsonEncode/Decode。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: Task 模型去 Hive 并新增 SQLite DAO`

---

## Task 12: TaskStore 改造（Provider → SQLite）

**Files:**
- Modify: `lib/services/task_store.dart`
- Test: `test/task_store_test.dart`、更新 `test/task_test.dart`

**Interfaces:**
- Consumes: TaskDao、ConflictDetector（复用现有纯 Dart 逻辑）、AuthService.currentUser。
- Produces（对外方法不变，内部换 SQLite）：
  - `Future<void> load()`；`Future<void> add(Task)`（内部走 addWithConflictCheck）；`Future<AddResult> addWithConflictCheck(Task)`；`Future<void> recheck(Task)`；`Future<void> toggleDone(int id)`（重复任务「完成今天」滚动种子）；`Future<void> remove(int id)` / `removeAll(List<int>)`。

- [ ] **Step 1-2:** 测试：add 后冲突检测产生 pendingConflict 且 effective=false；确认覆盖后生效；toggleDone 一次性；重复任务完成今天后种子滚动到下次并保持 pending。
Run: FAIL。
- [ ] **Step 3: 实现**：Provider `ChangeNotifier`，每次变更 `notifyListeners()`；写入后调用 `ReminderService.notifyTaskChanged`。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: TaskStore 迁移 SQLite 并保持冲突/完成语义`

---

## Task 13: ConflictDetector 回归适配

**Files:**
- Modify: `lib/services/conflict_detector.dart`（如需）
- Test: `test/conflict_detector_test.dart`（存量）

**Interfaces:**
- 保持现有纯函数签名；确认规则：资源占用冲突才阻断；时长 0 按 1 分钟参与；done 不占资源；无时间 → undated/effective=false。

- [ ] **Step 1:** 跑 `flutter test test/conflict_detector_test.dart`，确认存量测试仍绿。
- [ ] **Step 2:** 若因模型字段改名失败，更新测试到新模型（不改业务规则）。
- [ ] **Step 3:** `flutter test test/conflict_detector_test.dart` → PASS。
- [ ] **Step 4: Commit** → `test: 冲突检测回归适配 SQLite 模型`

---

## Task 14: ReminderService 基础重构（通知 22 + 响铃 + TTS）

**Files:**
- Modify: `lib/services/reminder_service.dart`、`lib/services/notification_service_io.dart`、`lib/services/audio_service.dart`
- Test: `test/reminder_service_test.dart`（用接口 mock 原生通道）

**Interfaces:**
- Produces:
  - `Future<void> init()`（初始化 flutter_local_notifications 22；timezone 锁 Asia/Shanghai）；
  - `Future<bool> requestPermissions()`（POST_NOTIFICATIONS / iOS 授权）；
  - `Future<void> scheduleAll(List<Task>)`（启动重排，重复任务派生多通知 id + matchDateTimeComponents）；
  - `Future<void> notifyTaskChanged(Task, {bool done})`（完成取消、否则重排）；
  - `Future<void> cancelAll()`；`void startInAppRing(String title)` / `void stopInAppRing()`（audioplayers 本地音频 + flutter_tts 循环 10s/间隔 2s）。

- [ ] **Step 1-2:** 单元测试（原生通道抽象为接口注入 mock）：scheduleAll 为每条任务派发正确 id 与 exact 调度；done 任务取消；重复任务派生多个；start/stop 响铃幂等。
Run: FAIL。
- [ ] **Step 3: 实现**：抽象接口 + IO 实现（真实插件只在 IO 实现出现，便于纯 Dart 测试）；exactAllowWhileIdle；注意 flutter_local_notifications 22 的 AndroidScheduleMode API 名。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: 提醒调度适配 notifications 22 + audioplayers 响铃/TTS`

---

## Task 15: 任务列表/添加页视觉升级（设计稿落地）

**Files:**
- Modify: `lib/modules/tasks/tasks_tab.dart`、`task_list.dart`、`add_task_screen.dart`
- Modify: `lib/widgets/task_card.dart`、`task_feedback_card.dart`、`speed_dial.dart`、`bottom_nav.dart`
- Test: 更新 `test/tasks_tab_filter_test.dart`、`test/task_card_selection_test.dart`、`test/task_visual_state_test.dart`、`test/filter_tab_bar_test.dart`、`test/snackbar_auto_dismiss_test.dart`

**Interfaces:**
- 视觉规则：筛选 Tab 圆角胶囊 + 数量角标；冲突卡红框 danger + 徽标 + 三按钮；完成态青绿勾选 + 降透明度；Speed Dial 手动/语音；触控 ≥48。
- 行为规则：滑动删除二次确认；长按选择模式批量删（先取消提醒）；addWithConflictCheck / recheck 链路不变。

- [ ] **Step 1:** 按设计稿更新 widgets（token 全部走 `Theme.of(context)`，禁止硬编码色值）。
- [ ] **Step 2:** 逐文件更新 widget 测试断言（用主题色值 + Key 语义，避免 golden 绑定实现细节）。
- [ ] **Step 3:** `flutter analyze` + `flutter test` 全绿。
- [ ] **Step 4: Commit** → `feat: 任务模块视觉与交互升级落地设计稿`

---

## Task 16: 我的页 + 备份 + 提醒引导页

**Files:**
- Create: `lib/screens/profile_page.dart`、`lib/screens/permission_guide_screen.dart`
- Create: `lib/services/backup_service.dart`
- Test: `test/backup_service_test.dart`、`test/profile_page_test.dart`

**Interfaces:**
- Produces:
  - `BackupService.exportJson(int userId) → Future<String>`（tasks + 用户偏好，不含 password_hash）；
  - `BackupService.importJson(int userId, String json) → Future<int>`（返回导入条数，校验字段名，失败抛中文异常）；
  - Profile：编辑昵称/头像(image_picker)/默认响铃时长；导出 share_plus、导入 file_picker；深色跟随系统；退出登录。
  - PermissionGuide：通知/电池优化/自启动清单；被拒 url_launcher 跳系统设置。

- [ ] **Step 1-2:** 测试：导出不含敏感字段；导入 round-trip 数量正确；导入损坏 JSON 抛错；Profile 退出后 session 清空。
Run: FAIL。
- [ ] **Step 3: 实现**。
- [ ] **Step 4:** PASS。
- [ ] **Step 5: Commit** → `feat: 我的页、JSON 备份与提醒引导页`

---

## Task 17: 阶段 1 集成验证与文档

**Files:**
- Modify: `README.md`、`PROGRESS.md`
- Test: 全量验证

- [ ] **Step 1:** `flutter analyze` → 0 error；`flutter test` → 全量绿。
- [ ] **Step 2:** 本机无 Android SDK，产出「真机冒烟清单」（登录→建任务→冲突→完成→提醒→导出导入→登出），交由有 SDK/真机的环境执行；冒烟项写入 PROGRESS.md。
- [ ] **Step 3:** 更新 README（依赖表、运行方式）与 PROGRESS。
- [ ] **Step 4: Commit** → `docs: 阶段 1 集成验证与冒烟清单`

---

## Self-Review（写完后自查）

**1. 规格覆盖（FEATURES.md ↔ Task）**
- 一、登录/用户管理 → Task 3/4/5/7/16 ✓
- 二、启动流程与路由 → Task 6 ✓
- 三、任务 3.1 数据模型 → Task 2/11 ✓；3.2A 手动录入 → Task 12/15 ✓；3.2B 语音 → 阶段 2（本计划显式拆分）✓；3.3 冲突检测 → Task 12/13 ✓；3.4 提醒调度 → Task 14 ✓；3.5 列表交互 → Task 15 ✓
- 四、记事本 → 阶段 3（独立计划）✓
- 五、提示词 → 阶段 2 ✓
- 六、生产化 P1 RRULE/长描述 → 阶段 4；P2 i18n/桌面 → 阶段 4 可选 ✓
- UI 设计规范 → Task 7/8/15/16 ✓

**2. 占位符扫描：** 除「阶段 2/3/4 各自独立计划」为显式拆分外，无 TBD/TODO；Task 4/5/6/7/12/16 的 Step 3 给出实现要点但代码由执行者按接口签名补全，接口签名已在本任务 Interfaces 块定义，符合「工程师只看到自己任务也能干活」的要求。

**3. 类型一致性：** `AuthResult{ok,error,user}`、`User`/`Session`/`Task` 模型、DAO 方法名（insert/update/delete/findById/listByUser）、ReminderService 五个公开方法在任务间一致；TaskStore 对外方法保持旧签名，避免下游页面大改。

---

## 阶段路线图（后续独立计划，按到达时再细化）

- **阶段 2 · 语音规划**：Aliyun ASR(DashScope) + 两份排期提示词（tasks_voice_scheduled/delay）+ 四态预览页 + 本地 NLP 兜底；独立计划 `2026-08-XX-shishuo-phase2.md`。
- **阶段 3 · 记事本**：SQLite v2 迁移新增六表 + 六大子功能表单/详情 + Hub 网格 + 自绘报表；独立计划。
- **阶段 4 · 上架准备**：应用图标、商店长描述、隐私说明、Android 厂商保活矩阵、可选 i18n 中英。

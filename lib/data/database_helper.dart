import 'package:sqflite/sqflite.dart';

/// 本地 SQLite 数据库单例：统一建表、迁移与读写入口。
///
/// 依赖 sqflite；所有业务表均携带 user_id 归属当前登录用户。
/// 版本策略：v1 建 users/session/tasks 三表；后续记事本六表在 v2 迁移中追加。
///
/// 注意：非线程安全，App 内单例使用，禁止并发 open/close；
/// 测试通过 [setFactoryForTest]/[setPathForTest] 注入 FFI 内存库。
class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  /// 测试注入：数据库工厂（如 sqflite_common_ffi 的 databaseFactoryFfi）
  static DatabaseFactory? _factoryOverride;

  /// 测试注入：数据库路径（如 inMemoryDatabasePath）
  static String? _pathOverride;

  static const _dbName = 'daily_planner.db';
  static const _dbVersion = 4;

  Database? _db;

  static void setFactoryForTest(DatabaseFactory factory) {
    _factoryOverride = factory;
  }

  static void setPathForTest(String path) {
    _pathOverride = path;
  }

  /// 获取（惰性创建）数据库连接
  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final factory = _factoryOverride ?? databaseFactory;
    final path = _pathOverride ?? '${await getDatabasesPath()}/$_dbName';
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// 首次建库：users（本地账户）+ session（单行登录态）+ tasks（任务）
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
        id TEXT PRIMARY KEY,
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
        trigger_type TEXT NOT NULL DEFAULT 'once',
        freq_type TEXT,
        freq_interval INTEGER NOT NULL DEFAULT 1,
        end_at TEXT,
        interval_seconds INTEGER,
        max_repeats INTEGER,
        repeat_count INTEGER NOT NULL DEFAULT 0,
        next_fire_time TEXT,
        prev_fire_time TEXT,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('CREATE INDEX idx_tasks_user ON tasks(user_id, status)');
    await _createUserSettingsTable(db);
    await _createNotebookTables(db);
  }

  /// 版本迁移入口：v2 追加记事本六表；v3 演进任务调度字段 + 用户提醒设置。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createNotebookTables(db);
    }
    if (oldVersion < 3) {
      await _upgradeV3(db);
    }
    if (oldVersion < 4) {
      await _upgradeV4(db);
    }
  }

  /// v4 迁移：购物项去掉「预期价」，实付列改名 price（单一金额）。
  ///
  /// SQLite 删列需重建表：建新表 → 映射拷贝（实付优先，实付为 0 时以预期
  /// 价兜底，避免丢失旧数据唯一金额信息）→ 删旧表 → 改名。
  Future<void> _upgradeV4(Database db) async {
    await db.execute('''
      CREATE TABLE shopping_items_v4(
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        cart_id TEXT,
        item TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        category TEXT,
        note TEXT,
        date TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(cart_id) REFERENCES shopping_carts(id) ON DELETE SET NULL
      )''');
    await db.execute('''
      INSERT INTO shopping_items_v4(id, user_id, cart_id, item, price, category, note, date, created_at)
      SELECT id, user_id, cart_id, item,
             CASE WHEN actual_price > 0 THEN actual_price ELSE expected_price END,
             category, note, date, created_at
      FROM shopping_items''');
    await db.execute('DROP TABLE shopping_items');
    await db.execute('ALTER TABLE shopping_items_v4 RENAME TO shopping_items');
  }

  /// v3 迁移：任务表对齐统一调度表（task_schedule）关键字段，
  /// 并将旧数据归位（repeat→trigger_type/freq_type、missed→pending）。
  Future<void> _upgradeV3(Database db) async {
    await db.execute(
        "ALTER TABLE tasks ADD COLUMN trigger_type TEXT NOT NULL DEFAULT 'once'");
    await db.execute('ALTER TABLE tasks ADD COLUMN freq_type TEXT');
    await db.execute(
        'ALTER TABLE tasks ADD COLUMN freq_interval INTEGER NOT NULL DEFAULT 1');
    await db.execute('ALTER TABLE tasks ADD COLUMN end_at TEXT');
    await db.execute('ALTER TABLE tasks ADD COLUMN interval_seconds INTEGER');
    await db.execute('ALTER TABLE tasks ADD COLUMN max_repeats INTEGER');
    await db.execute(
        'ALTER TABLE tasks ADD COLUMN repeat_count INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE tasks ADD COLUMN next_fire_time TEXT');
    await db.execute('ALTER TABLE tasks ADD COLUMN prev_fire_time TEXT');
    // 旧数据归位：有重复方式的按日历周期重复（RECURRING），一次性保持 ONCE
    await db.execute(
        "UPDATE tasks SET trigger_type = 'recurring' WHERE repeat != 'none'");
    await db.execute(
        "UPDATE tasks SET freq_type = 'day' WHERE repeat = 'daily'");
    await db.execute(
        "UPDATE tasks SET freq_type = 'week' WHERE repeat IN ('weekly','weekdays','custom')");
    // 逾期状态已移除：历史 missed 统一归为 pending
    await db.execute("UPDATE tasks SET status = 'pending' WHERE status = 'missed'");
    await _createUserSettingsTable(db);
  }

  /// 用户提醒设置表：铃铛浮层（静音/震动/语音 + 音量）的持久化位置。
  Future<void> _createUserSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_settings(
        user_id INTEGER PRIMARY KEY,
        reminder_mode TEXT NOT NULL DEFAULT 'voice',
        vibrate INTEGER NOT NULL DEFAULT 1,
        reminder_volume INTEGER NOT NULL DEFAULT 60,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
  }

  /// 记事本十张表（FEATURES 4.1）：购物 2 / 账本 1 / 读书 1 / 旅游 3 / 学习 2 / 菜谱 1。
  /// 嵌套结构（交通/计费/配料/步骤）以 TEXT JSON 列存储；id 为客户端 UUID。
  Future<void> _createNotebookTables(Database db) async {
    await db.execute('''
      CREATE TABLE shopping_carts(
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE shopping_items(
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        cart_id TEXT,
        item TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        category TEXT,
        note TEXT,
        date TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(cart_id) REFERENCES shopping_carts(id) ON DELETE SET NULL
      )''');
    await db.execute('''
      CREATE TABLE ledger(
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        kind TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT,
        date TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE reading(
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        status TEXT NOT NULL,
        rating INTEGER NOT NULL DEFAULT 0,
        category TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE trips(
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        city TEXT,
        home_city TEXT,
        start_date TEXT,
        end_date TEXT,
        intercity_transport TEXT,
        hotel TEXT,
        transports TEXT,
        total_cost REAL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE trip_days(
        id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        date TEXT,
        label TEXT,
        sort INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(trip_id) REFERENCES trips(id) ON DELETE CASCADE,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE trip_checkpoints(
        id TEXT PRIMARY KEY,
        day_id TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        transport TEXT,
        billings TEXT,
        done INTEGER NOT NULL DEFAULT 0,
        rating INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        sort INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(day_id) REFERENCES trip_days(id) ON DELETE CASCADE,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE courses(
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        source TEXT,
        status TEXT NOT NULL,
        progress INTEGER NOT NULL DEFAULT 0,
        rating INTEGER NOT NULL DEFAULT 0,
        category TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE study_records(
        id TEXT PRIMARY KEY,
        course_id TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        content TEXT,
        rating INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(course_id) REFERENCES courses(id) ON DELETE CASCADE,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE recipes(
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        category TEXT,
        ingredients TEXT,
        steps TEXT,
        difficulty TEXT NOT NULL,
        rating INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

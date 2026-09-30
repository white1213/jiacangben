import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../consts.dart';

/// 数据库初始化、建表、版本迁移（单例）
class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const int dbVersion = 3; // v3：media_attachment / entry_template / saved_filter 三表

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, kDbName),
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    // 自愈式 schema 校验：修复由历史缺陷版本（如 v1.2.0 的 onCreate 缺列）初始化的库。
    // 此时 DB 版本号已是最新，onUpgrade 不会再触发，只能在此幂等补齐。
    await _ensureSchema(db);
    return db;
  }

  /// 幂等补齐缺失的表与列（每次打开执行一次，正常库无副作用）
  Future<void> _ensureSchema(Database db) async {
    // 缺失的表：IF NOT EXISTS 幂等
    await db.execute('CREATE TABLE IF NOT EXISTS item_category ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, targetType TEXT NOT NULL, note TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS media_attachment ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, ownerType TEXT NOT NULL, ownerId INTEGER NOT NULL, '
        'localFilePath TEXT NOT NULL, createTime TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS entry_template ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, targetType TEXT NOT NULL, presetFields TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS saved_filter ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, targetType TEXT NOT NULL, filterJson TEXT)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_item_category_target ON item_category(targetType)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_media_attachment_owner ON media_attachment(ownerType, ownerId)');
    // 缺失的列：ALTER 失败（列已存在）则忽略
    await _addColumnIfMissing(db, 'home_supply', 'categoryId', 'INTEGER');
    await _addColumnIfMissing(db, 'stored_item', 'categoryId', 'INTEGER');
  }

  Future<void> _addColumnIfMissing(Database db, String table, String column, String type) async {
    try {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      final exists = rows.any((row) => row['name'] == column);
      if (!exists) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      }
    } catch (_) {
      // 校验失败不阻断打开（例如表尚不存在，onCreate/onUpgrade 会处理）
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 全新安装：直接按当前版本（v3）的完整结构建表，与 onUpgrade 增量迁移的结果保持一致
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE storage_location (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE stored_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 1,
        locationId INTEGER,
        categoryId INTEGER,
        note TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE home_supply (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        purchaseDate TEXT NOT NULL,
        expireDate TEXT NOT NULL,
        isOpened INTEGER NOT NULL DEFAULT 0,
        openDate TEXT,
        afterOpenDays INTEGER,
        categoryId INTEGER,
        note TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE tag (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');
    batch.execute('''
      CREATE TABLE tag_relation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ownerType TEXT NOT NULL,
        ownerId INTEGER NOT NULL,
        tagId INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE item_category (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        targetType TEXT NOT NULL,
        note TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE media_attachment (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ownerType TEXT NOT NULL,
        ownerId INTEGER NOT NULL,
        localFilePath TEXT NOT NULL,
        createTime TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE entry_template (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        targetType TEXT NOT NULL,
        presetFields TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE saved_filter (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        targetType TEXT NOT NULL,
        filterJson TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_stored_item_location ON stored_item(locationId)');
    batch.execute('CREATE INDEX idx_tag_relation_owner ON tag_relation(ownerType, ownerId)');
    batch.execute('CREATE INDEX idx_tag_relation_tag ON tag_relation(tagId)');
    batch.execute('CREATE INDEX idx_item_category_target ON item_category(targetType)');
    batch.execute('CREATE INDEX idx_media_attachment_owner ON media_attachment(ownerType, ownerId)');
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 -> v2：新增 item_category 表；home_supply / stored_item 增加 categoryId（默认 null）。
    // ALTER TABLE ADD COLUMN 对已有数据无损，老用户数据完整保留。
    if (oldVersion < 2) {
      final batch = db.batch();
      batch.execute('''
        CREATE TABLE IF NOT EXISTS item_category (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          targetType TEXT NOT NULL,
          note TEXT
        )
      ''');
      batch.execute('ALTER TABLE home_supply ADD COLUMN categoryId INTEGER');
      batch.execute('ALTER TABLE stored_item ADD COLUMN categoryId INTEGER');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_item_category_target ON item_category(targetType)');
      await batch.commit(noResult: true);
    }
    // v2 -> v3：新增媒体附件、录入模板、保存筛选条件三张表
    if (oldVersion < 3) {
      final batch = db.batch();
      batch.execute('''
        CREATE TABLE IF NOT EXISTS media_attachment (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ownerType TEXT NOT NULL,
          ownerId INTEGER NOT NULL,
          localFilePath TEXT NOT NULL,
          createTime TEXT NOT NULL
        )
      ''');
      batch.execute('''
        CREATE TABLE IF NOT EXISTS entry_template (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          targetType TEXT NOT NULL,
          presetFields TEXT
        )
      ''');
      batch.execute('''
        CREATE TABLE IF NOT EXISTS saved_filter (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          targetType TEXT NOT NULL,
          filterJson TEXT
        )
      ''');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_media_attachment_owner ON media_attachment(ownerType, ownerId)');
      await batch.commit(noResult: true);
    }
  }
}

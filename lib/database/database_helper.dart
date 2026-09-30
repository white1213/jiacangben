import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../consts.dart';

/// 数据库初始化、建表、版本迁移（单例）
class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const int dbVersion = 2; // v2：新增 item_category 表 + categoryId 字段

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, kDbName),
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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
    batch.execute('CREATE INDEX idx_stored_item_location ON stored_item(locationId)');
    batch.execute('CREATE INDEX idx_tag_relation_owner ON tag_relation(ownerType, ownerId)');
    batch.execute('CREATE INDEX idx_tag_relation_tag ON tag_relation(tagId)');
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
  }
}

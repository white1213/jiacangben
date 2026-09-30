import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../consts.dart';

/// 数据库初始化、建表、版本迁移（单例）
class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const int dbVersion = 1;

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
    // 预留：后续版本的增量迁移在此追加
  }
}

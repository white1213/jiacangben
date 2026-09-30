

import '../model/storage_location.dart';
import '../model/tag_relation.dart';
import 'database_helper.dart';

/// 收纳位置数据服务（写入全部走事务）
class LocationService {
  static const String _table = 'storage_location';

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<StorageLocation>> listAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query(_table, orderBy: 'name ASC');
    return rows.map(StorageLocation.fromMap).toList();
  }

  Future<int> insert(StorageLocation location) async {
    final db = await _dbHelper.database;
    return db.transaction((txn) => txn.insert(_table, location.toMap()));
  }

  Future<void> update(StorageLocation location) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) => txn.update(
          _table,
          location.toMap(),
          where: 'id = ?',
          whereArgs: [location.id],
        ));
  }

  /// 各位置下的物件数量：locationId -> count
  Future<Map<int, int>> itemCountsByLocation() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT locationId, COUNT(*) AS c FROM stored_item WHERE locationId IS NOT NULL GROUP BY locationId',
    );
    return {for (final row in rows) row['locationId'] as int: row['c'] as int};
  }

  Future<int> countItems(int locationId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM stored_item WHERE locationId = ?',
      [locationId],
    );
    return rows.first['c'] as int;
  }

  /// v1.2：该位置下全部物件 id（删除位置时用于级联清理附件）
  Future<List<int>> ownedItemIds(int locationId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'stored_item',
      columns: ['id'],
      where: 'locationId = ?',
      whereArgs: [locationId],
    );
    return rows.map((row) => row['id'] as int).toList();
  }

  /// 删除收纳位置（禁止静默级联删除，必须由调用方显式选择处理方式）：
  /// - [alsoDeleteItems] = false：位置下所有物件 locationId 置空（物件保留，改为未归位）
  /// - [alsoDeleteItems] = true：连同位置下全部物件及其标签关联一并删除
  Future<void> delete(int id, {required bool alsoDeleteItems}) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      if (alsoDeleteItems) {
        final items = await txn.query('stored_item', columns: ['id'], where: 'locationId = ?', whereArgs: [id]);
        for (final item in items) {
          await txn.delete(
            'tag_relation',
            where: 'ownerType = ? AND ownerId = ?',
            whereArgs: [TagRelation.ownerTypeStoredItem, item['id']],
          );
        }
        await txn.delete('stored_item', where: 'locationId = ?', whereArgs: [id]);
      } else {
        await txn.update(
          'stored_item',
          {'locationId': null},
          where: 'locationId = ?',
          whereArgs: [id],
        );
      }
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
    });
  }
}

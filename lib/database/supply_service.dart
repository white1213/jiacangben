

import '../model/home_supply.dart';
import '../model/tag_relation.dart';
import '../utils/date_utils.dart';
import 'database_helper.dart';
import 'tag_service.dart';

/// 消耗物资数据服务（写入全部走事务）
class SupplyService {
  static const String _table = 'home_supply';

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<HomeSupply>> listAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query(_table, orderBy: 'expireDate ASC');
    return rows.map(HomeSupply.fromMap).toList();
  }

  /// 按名称或备注模糊搜索
  Future<List<HomeSupply>> search(String keyword) async {
    final kw = '%${keyword.trim()}%';
    final db = await _dbHelper.database;
    final rows = await db.query(
      _table,
      where: "name LIKE ? OR IFNULL(note, '') LIKE ?",
      whereArgs: [kw, kw],
      orderBy: 'expireDate ASC',
    );
    return rows.map(HomeSupply.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $_table');
    return rows.first['c'] as int;
  }

  /// 新增（连同标签关联，单事务）
  Future<void> insert(HomeSupply supply, {Set<int> tagIds = const {}}) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final id = await txn.insert(_table, supply.toMap());
      await TagService.replaceRelations(txn, TagRelation.ownerTypeSupply, id, tagIds);
    });
  }

  /// 更新（连同标签关联整体替换，单事务）
  Future<void> update(HomeSupply supply, {required Set<int> tagIds}) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(_table, supply.toMap(), where: 'id = ?', whereArgs: [supply.id]);
      await TagService.replaceRelations(txn, TagRelation.ownerTypeSupply, supply.id!, tagIds);
    });
  }

  /// 删除（连同标签关联，单事务）
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'tag_relation',
        where: 'ownerType = ? AND ownerId = ?',
        whereArgs: [TagRelation.ownerTypeSupply, id],
      );
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
    });
  }

  /// v1.1 批量操作：批量标记为已开封（开封日期 = 当前 UTC 时间）。
  /// 已开封的条目跳过；单事务完成，返回实际标记的数量。
  Future<int> batchMarkOpened(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await _dbHelper.database;
    final now = utcNow().toIso8601String();
    return db.transaction<int>((txn) async {
      var marked = 0;
      for (final id in ids) {
        final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) continue;
        final supply = HomeSupply.fromMap(rows.first);
        if (supply.isOpened) continue;
        await txn.update(
          _table,
          {'isOpened': 1, 'openDate': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        marked++;
      }
      return marked;
    });
  }

  /// v1.1 批量操作：批量删除（连同标签关联，单事务），返回删除数量
  Future<int> batchDelete(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await _dbHelper.database;
    return db.transaction<int>((txn) async {
      var deleted = 0;
      for (final id in ids) {
        await txn.delete(
          'tag_relation',
          where: 'ownerType = ? AND ownerId = ?',
          whereArgs: [TagRelation.ownerTypeSupply, id],
        );
        deleted += await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
      }
      return deleted;
    });
  }
}

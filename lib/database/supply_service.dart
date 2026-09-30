

import '../model/home_supply.dart';
import '../model/tag_relation.dart';
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
}

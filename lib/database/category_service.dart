

import '../model/item_category.dart';
import 'database_helper.dart';

/// v1.1：分类数据服务
class CategoryService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 按 targetType 查询（null = 全部）
  Future<List<ItemCategory>> listAll({String? targetType}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'item_category',
      where: targetType == null ? null : 'targetType = ?',
      whereArgs: targetType == null ? null : [targetType],
      orderBy: 'name ASC',
    );
    return rows.map(ItemCategory.fromMap).toList();
  }

  Future<int> insert(ItemCategory category) async {
    final db = await _dbHelper.database;
    return db.transaction((txn) => txn.insert('item_category', category.toMap()));
  }

  Future<void> update(ItemCategory category) async {
    final db = await _dbHelper.database;
    await db.transaction(
      (txn) => txn.update('item_category', category.toMap(), where: 'id = ?', whereArgs: [category.id]),
    );
  }

  /// 引用计数：categoryId -> 引用次数（物资表 + 物件表合计）
  /// 删除前校验用：存在引用则禁止删除
  Future<Map<int, int>> usageCounts() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT categoryId, COUNT(*) AS c FROM (
        SELECT categoryId FROM home_supply WHERE categoryId IS NOT NULL
        UNION ALL
        SELECT categoryId FROM stored_item WHERE categoryId IS NOT NULL
      ) GROUP BY categoryId
    ''');
    return {for (final row in rows) row['categoryId'] as int: row['c'] as int};
  }

  /// 删除分类（引用校验由页面层完成，此处保证事务）
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) => txn.delete('item_category', where: 'id = ?', whereArgs: [id]));
  }
}

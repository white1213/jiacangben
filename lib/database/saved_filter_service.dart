import '../model/saved_filter.dart';
import 'database_helper.dart';

/// v1.2：保存筛选条件数据服务
class SavedFilterService {
  Future<List<SavedFilter>> listAll(String targetType) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'saved_filter',
      where: 'targetType = ?',
      whereArgs: [targetType],
      orderBy: 'name ASC',
    );
    return rows.map(SavedFilter.fromMap).toList();
  }

  Future<int> insert(SavedFilter filter) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction((txn) => txn.insert('saved_filter', filter.toMap()));
  }

  Future<void> update(SavedFilter filter) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction(
      (txn) => txn.update('saved_filter', filter.toMap(), where: 'id = ?', whereArgs: [filter.id]),
    );
  }

  Future<void> delete(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) => txn.delete('saved_filter', where: 'id = ?', whereArgs: [id]));
  }
}

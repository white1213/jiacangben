import '../model/entry_template.dart';
import 'database_helper.dart';

/// v1.2：录入模板数据服务
class TemplateService {
  Future<List<EntryTemplate>> listAll({String? targetType}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'entry_template',
      where: targetType == null ? null : 'targetType = ?',
      whereArgs: targetType == null ? null : [targetType],
      orderBy: 'name ASC',
    );
    return rows.map(EntryTemplate.fromMap).toList();
  }

  Future<int> insert(EntryTemplate template) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction((txn) => txn.insert('entry_template', template.toMap()));
  }

  Future<void> update(EntryTemplate template) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction(
      (txn) => txn.update('entry_template', template.toMap(), where: 'id = ?', whereArgs: [template.id]),
    );
  }

  Future<void> delete(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) => txn.delete('entry_template', where: 'id = ?', whereArgs: [id]));
  }
}

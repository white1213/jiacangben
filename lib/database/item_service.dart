

import '../model/stored_item.dart';
import '../model/tag_relation.dart';
import 'database_helper.dart';
import 'tag_service.dart';

/// 普通物件数据服务（写入全部走事务）
class ItemService {
  static const String _table = 'stored_item';

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<StoredItem>> listAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query(_table, orderBy: 'name ASC');
    return rows.map(StoredItem.fromMap).toList();
  }

  Future<List<StoredItem>> listByLocation(int locationId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(_table, where: 'locationId = ?', whereArgs: [locationId], orderBy: 'name ASC');
    return rows.map(StoredItem.fromMap).toList();
  }

  Future<List<StoredItem>> search(String keyword) async {
    final kw = '%${keyword.trim()}%';
    final db = await _dbHelper.database;
    final rows = await db.query(
      _table,
      where: "name LIKE ? OR IFNULL(note, '') LIKE ?",
      whereArgs: [kw, kw],
      orderBy: 'name ASC',
    );
    return rows.map(StoredItem.fromMap).toList();
  }

  /// v1.3：组合筛选查询（分类 + 标签 OR + 关键词），供列表页筛选弹窗与子集导出使用。
  /// 标签为 OR 语义：至少拥有任意一个选中标签的条目即返回（tag_relation 子查询）。
  Future<List<StoredItem>> listFiltered({
    String? keyword,
    int? categoryId,
    Set<int> tagIds = const {},
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (keyword != null && keyword.trim().isNotEmpty) {
      final kw = '%${keyword.trim()}%';
      where.add("(name LIKE ? OR IFNULL(note, '') LIKE ?)");
      args..add(kw)..add(kw);
    }
    if (categoryId != null) {
      where.add('categoryId = ?');
      args.add(categoryId);
    }
    if (tagIds.isNotEmpty) {
      final placeholders = List.filled(tagIds.length, '?').join(',');
      where.add(
        "EXISTS (SELECT 1 FROM tag_relation tr "
        "WHERE tr.ownerType = 'storedItem' AND tr.ownerId = stored_item.id AND tr.tagId IN ($placeholders))",
      );
      args.addAll(tagIds);
    }
    final db = await _dbHelper.database;
    final rows = await db.query(
      _table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'name ASC',
    );
    return rows.map(StoredItem.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $_table');
    return rows.first['c'] as int;
  }

  /// 新增（连同标签关联，单事务）
  Future<void> insert(StoredItem item, {Set<int> tagIds = const {}}) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final id = await txn.insert(_table, item.toMap());
      await TagService.replaceRelations(txn, TagRelation.ownerTypeStoredItem, id, tagIds);
    });
  }

  /// 更新（修改归属位置即在此完成；连同标签关联整体替换，单事务）
  Future<void> update(StoredItem item, {required Set<int> tagIds}) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(_table, item.toMap(), where: 'id = ?', whereArgs: [item.id]);
      await TagService.replaceRelations(txn, TagRelation.ownerTypeStoredItem, item.id!, tagIds);
    });
  }

  /// 删除（连同标签关联，单事务）
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'tag_relation',
        where: 'ownerType = ? AND ownerId = ?',
        whereArgs: [TagRelation.ownerTypeStoredItem, id],
      );
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
    });
  }

  /// v1.1 批量操作：批量迁移到目标收纳位置（locationId 传 null = 全部改为未归位），单事务
  Future<int> batchMove(List<int> ids, int? locationId) async {
    if (ids.isEmpty) return 0;
    final db = await _dbHelper.database;
    return db.transaction<int>((txn) async {
      var moved = 0;
      for (final id in ids) {
        moved += await txn.update(
          _table,
          {'locationId': locationId},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return moved;
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
          whereArgs: [TagRelation.ownerTypeStoredItem, id],
        );
        deleted += await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
      }
      return deleted;
    });
  }
}

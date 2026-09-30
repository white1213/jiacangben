import 'package:sqflite/sqflite.dart';

import '../model/tag.dart';
import 'database_helper.dart';

/// 标签数据服务
class TagService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Tag>> listAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query('tag', orderBy: 'name ASC');
    return rows.map(Tag.fromMap).toList();
  }

  /// 已存在（同名）则返回，否则新建；事务保证并发下同名不重复
  Future<Tag> getOrCreate(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError('标签名不能为空');
    }
    final db = await _dbHelper.database;
    return db.transaction<Tag>((txn) async {
      final rows = await txn.query('tag', where: 'name = ?', whereArgs: [name], limit: 1);
      if (rows.isNotEmpty) {
        return Tag.fromMap(rows.first);
      }
      final id = await txn.insert('tag', {'name': name});
      return Tag(id: id, name: name);
    });
  }

  /// 在同一事务内整体替换某记录的标签关联（先删后插）
  static Future<void> replaceRelations(
    DatabaseExecutor exec,
    String ownerType,
    int ownerId,
    Set<int> tagIds,
  ) async {
    await exec.delete(
      'tag_relation',
      where: 'ownerType = ? AND ownerId = ?',
      whereArgs: [ownerType, ownerId],
    );
    for (final tagId in tagIds) {
      await exec.insert('tag_relation', {
        'ownerType': ownerType,
        'ownerId': ownerId,
        'tagId': tagId,
      });
    }
  }

  /// 批量查询标签：ownerId -> 标签列表
  Future<Map<int, List<Tag>>> tagsByOwner(String ownerType) async {
    final db = await _dbHelper.database;
    final relations = await db.query('tag_relation', where: 'ownerType = ?', whereArgs: [ownerType]);
    final tags = await listAll();
    final tagById = {for (final t in tags) if (t.id != null) t.id!: t};
    final result = <int, List<Tag>>{};
    for (final rel in relations) {
      final ownerId = rel['ownerId'] as int;
      final tag = tagById[rel['tagId'] as int];
      if (tag != null) {
        (result[ownerId] ??= []).add(tag);
      }
    }
    return result;
  }

  /// v1.1：各标签的关联计数：tagId -> 关联的物资/物件数量
  Future<Map<int, int>> relationCounts() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT tagId, COUNT(*) AS c FROM tag_relation GROUP BY tagId',
    );
    return {for (final row in rows) row['tagId'] as int: row['c'] as int};
  }

  /// v1.1：重命名标签（单事务）。若目标名已存在则抛 StateError，由页面提示。
  Future<void> rename(int tagId, String newName) async {
    final name = newName.trim();
    if (name.isEmpty) {
      throw ArgumentError('标签名不能为空');
    }
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final dup = await txn.query('tag', where: 'name = ? AND id != ?', whereArgs: [name, tagId], limit: 1);
      if (dup.isNotEmpty) {
        throw StateError('标签「$name」已存在');
      }
      // 关联记录通过 tagId 引用标签，改名不影响关联；整个操作置于事务保证一致性
      await txn.update('tag', {'name': name}, where: 'id = ?', whereArgs: [tagId]);
    });
  }

  /// v1.1：仅当标签无任何关联记录时才允许删除，返回是否删除成功
  Future<bool> deleteIfUnused(int tagId) async {
    final db = await _dbHelper.database;
    return db.transaction<bool>((txn) async {
      final relations = await txn.query(
        'tag_relation',
        where: 'tagId = ?',
        whereArgs: [tagId],
        limit: 1,
      );
      if (relations.isNotEmpty) return false;
      await txn.delete('tag', where: 'id = ?', whereArgs: [tagId]);
      return true;
    });
  }
}

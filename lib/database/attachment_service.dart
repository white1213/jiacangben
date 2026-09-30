import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../model/media_attachment.dart';
import 'database_helper.dart';

/// v1.2：媒体附件数据服务。
/// 数据库只存本地文件路径；图片文件复制到应用外部存储目录（卸载不随缓存清掉）。
class AttachmentService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 图片存放根目录：优先外部存储目录（App 专属外部目录，无需权限），
  /// 拿不到时回退应用文档目录。
  Future<Directory> mediaRoot() async {
    Directory base = (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'attachments'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<List<MediaAttachment>> listByOwner(String ownerType, int ownerId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'media_attachment',
      where: 'ownerType = ? AND ownerId = ?',
      whereArgs: [ownerType, ownerId],
      orderBy: 'id ASC',
    );
    return rows.map(MediaAttachment.fromMap).toList();
  }

  Future<int> countByOwners(String ownerType, List<int> ownerIds) async {
    if (ownerIds.isEmpty) return 0;
    final db = await _dbHelper.database;
    final placeholders = List.filled(ownerIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM media_attachment WHERE ownerType = ? AND ownerId IN ($placeholders)',
      [ownerType, ...ownerIds],
    );
    return rows.first['c'] as int;
  }

  /// 把选中的图片复制到应用媒体目录并登记（单事务）
  Future<void> addImages(String ownerType, int ownerId, List<String> pickedPaths) async {
    if (pickedPaths.isEmpty) return;
    final root = await mediaRoot();
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final src in pickedPaths) {
        final source = File(src);
        if (!source.existsSync()) continue;
        final ext = p.extension(src).toLowerCase();
        final fileName = '${ownerType}_${ownerId}_${DateTime.now().microsecondsSinceEpoch}$ext';
        final dest = await source.copy(p.join(root.path, fileName));
        await txn.insert('media_attachment', {
          'ownerType': ownerType,
          'ownerId': ownerId,
          'localFilePath': dest.path,
          'createTime': now,
        });
      }
    });
  }

  /// 删除单条附件记录（单事务），可选同时删除图片文件
  Future<void> deleteSingle(MediaAttachment attachment, {required bool deleteFile}) async {
    final db = await _dbHelper.database;
    await db.transaction(
      (txn) => txn.delete('media_attachment', where: 'id = ?', whereArgs: [attachment.id]),
    );
    if (deleteFile) {
      try {
        final f = File(attachment.localFilePath);
        if (f.existsSync()) await f.delete();
      } catch (_) {
        // 文件删除失败不阻断
      }
    }
  }

  /// 清理一批记录的附件记录；[deleteFiles]=true 时同时删除图片文件。
  /// 返回删除的文件数。
  Future<int> purgeForOwners(String ownerType, List<int> ownerIds, {required bool deleteFiles}) async {
    if (ownerIds.isEmpty) return 0;
    final db = await _dbHelper.database;
    final placeholders = List.filled(ownerIds.length, '?').join(',');
    final rows = await db.query(
      'media_attachment',
      where: 'ownerType = ? AND ownerId IN ($placeholders)',
      whereArgs: [ownerType, ...ownerIds],
    );
    await db.transaction((txn) async {
      await txn.delete(
        'media_attachment',
        where: 'ownerType = ? AND ownerId IN ($placeholders)',
        whereArgs: [ownerType, ...ownerIds],
      );
    });
    var files = 0;
    if (deleteFiles) {
      for (final row in rows) {
        try {
          final f = File(row['localFilePath'] as String);
          if (f.existsSync()) {
            await f.delete();
            files++;
          }
        } catch (_) {
          // 单个文件删除失败不阻断整体清理
        }
      }
    }
    return files;
  }
}

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../consts.dart';
import '../database/database_helper.dart';
import '../model/consume_log.dart';
import '../model/entry_template.dart';
import '../model/home_supply.dart';
import '../model/saved_filter.dart';
import '../model/storage_location.dart';
import '../model/stored_item.dart';
import '../model/tag.dart';
import '../model/tag_relation.dart';
import '../utils/date_utils.dart';

/// 备份与恢复服务：全量 JSON 导出 / 校验 / 事务导入
class BackupService {
  /// 导出全部数据库记录
  Future<Map<String, Object?>> exportAll() async {
    final db = await DatabaseHelper.instance.database;
    return <String, Object?>{
      'app': kAppName,
      'schemaVersion': 1,
      'appVersion': kAppVersion,
      'exportedAt': utcNow().toIso8601String(),
      'storageLocation': await db.query('storage_location', orderBy: 'id'),
      'storedItem': await db.query('stored_item', orderBy: 'id'),
      'homeSupply': await db.query('home_supply', orderBy: 'id'),
      'tag': await db.query('tag', orderBy: 'id'),
      'tagRelation': await db.query('tag_relation', orderBy: 'id'),
      // v1.2：录入模板与保存筛选为纯数据，纳入备份；图片附件（media_attachment）不进 JSON 备份
      'entryTemplate': await db.query('entry_template', orderBy: 'id'),
      'savedFilter': await db.query('saved_filter', orderBy: 'id'),
      // v1.4：领用出库流水纳入备份
      'consumeLog': await db.query('consume_log', orderBy: 'id'),
    };
  }

  /// 导出为本地 JSON 文件，写入应用文档目录的 backups 子目录
  Future<File> exportToFile() async {
    final dir = await backupDirectory();
    final stamp = _localStamp(DateTime.now());
    final file = File(p.join(dir.path, 'jiacangben_backup_$stamp.json'));
    final json = const JsonEncoder.withIndent('  ').convert(await exportAll());
    await file.writeAsString(json, flush: true);
    return file;
  }

  /// 备份目录下的全部 JSON 文件（新->旧）
  Future<List<File>> listBackupFiles() async {
    final dir = await backupDirectory();
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.json'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// 导入前校验：JSON 语法 + 结构 + 每条记录可解析为对应 Model。
  /// 不合法抛 [FormatException]，message 为中文提示。
  Map<String, Object?> validate(String jsonText) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      throw const FormatException('JSON 解析失败：内容不是合法的 JSON 文本');
    }
    if (decoded is! Map) {
      throw const FormatException('JSON 结构错误：根节点必须是对象');
    }
    // v1.3：版本标记校验——只接受本应用导出、schema 版本可识别的备份，防止误导入不兼容文件
    final app = decoded['app'];
    if (app is! String || app != kAppName) {
      throw const FormatException('这不是「家藏本」导出的备份文件（缺少应用标识），已拒绝导入');
    }
    final schema = decoded['schemaVersion'];
    if (schema is! num || schema.toInt() < 1 || schema.toInt() > 1) {
      throw FormatException('备份 schema 版本（$schema）不受当前 App 支持，请先升级 App 或使用对应版本导出的备份');
    }
    const listKeys = ['storageLocation', 'storedItem', 'homeSupply', 'tag', 'tagRelation'];
    for (final key in listKeys) {
      if (decoded[key] is! List) {
        throw FormatException('JSON 结构错误：缺少字段 "$key" 或其不是数组');
      }
    }
    try {
      for (final row in decoded['homeSupply'] as List) {
        HomeSupply.fromMap(_asRowMap(row, 'homeSupply'));
      }
      for (final row in decoded['storedItem'] as List) {
        StoredItem.fromMap(_asRowMap(row, 'storedItem'));
      }
      for (final row in decoded['storageLocation'] as List) {
        StorageLocation.fromMap(_asRowMap(row, 'storageLocation'));
      }
      for (final row in decoded['tag'] as List) {
        Tag.fromMap(_asRowMap(row, 'tag'));
      }
      for (final row in decoded['tagRelation'] as List) {
        TagRelation.fromMap(_asRowMap(row, 'tagRelation'));
      }
      // v1.2 新增表：旧版（v1.1 及之前）备份没有这两个字段，缺省视为空
      for (final row in (decoded['entryTemplate'] as List?) ?? const []) {
        EntryTemplate.fromMap(_asRowMap(row, 'entryTemplate'));
      }
      for (final row in (decoded['savedFilter'] as List?) ?? const []) {
        SavedFilter.fromMap(_asRowMap(row, 'savedFilter'));
      }
      // v1.4：领用出库流水（旧备份缺该键视为空）
      for (final row in (decoded['consumeLog'] as List?) ?? const []) {
        ConsumeLog.fromMap(_asRowMap(row, 'consumeLog'));
      }
    } catch (e) {
      throw FormatException('数据校验失败：$e');
    }
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 全量覆盖导入（单事务）：先清空相关表，再按导出顺序原样写回，
  /// 保留原始 id，位置归属 / 标签关联不断裂；任一步失败整体回滚。
  /// 返回写入的总记录数。
  Future<int> importAll(String jsonText) async {
    final data = validate(jsonText);
    final db = await DatabaseHelper.instance.database;
    var total = 0;
    await db.transaction((txn) async {
      for (final table in [
        'tag_relation',
        'home_supply',
        'stored_item',
        'storage_location',
        'tag',
        'entry_template',
        'saved_filter',
        'consume_log',
      ]) {
        await txn.delete(table);
      }
      total += await _bulkInsert(txn, 'storage_location', data['storageLocation'] as List);
      total += await _bulkInsert(txn, 'stored_item', data['storedItem'] as List);
      total += await _bulkInsert(txn, 'home_supply', data['homeSupply'] as List);
      total += await _bulkInsert(txn, 'tag', data['tag'] as List);
      total += await _bulkInsert(txn, 'tag_relation', data['tagRelation'] as List);
      total += await _bulkInsert(txn, 'entry_template', (data['entryTemplate'] as List?) ?? const []);
      total += await _bulkInsert(txn, 'saved_filter', (data['savedFilter'] as List?) ?? const []);
      total += await _bulkInsert(txn, 'consume_log', (data['consumeLog'] as List?) ?? const []);
    });
    return total;
  }

  Future<int> _bulkInsert(DatabaseExecutor txn, String table, List rows) async {
    var n = 0;
    for (final row in rows) {
      await txn.insert(table, _asRowMap(row, table));
      n++;
    }
    return n;
  }

  Map<String, Object?> _asRowMap(Object? row, String table) {
    if (row is! Map) {
      throw ArgumentError('$table 中存在非对象记录');
    }
    return row.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 应用备份目录（应用文档目录 / backups），公开给子集导出等服务复用
  Future<Directory> backupDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, kBackupDirName));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  String _localStamp(DateTime local) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}${two(local.month)}${two(local.day)}_${two(local.hour)}${two(local.minute)}${two(local.second)}';
  }
}

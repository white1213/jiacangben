
import '../model/consume_log.dart';
import '../utils/date_utils.dart';
import 'database_helper.dart';

/// v1.4：物资领用出库流水服务。
/// 库存扣减与流水写入在同一事务；流水只写只读，不提供修改/删除接口（不可篡改）。
class ConsumeLogService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 领用出库：扣减 home_supply.count + 写入 consume_log（单事务）。
  /// 校验：领用数量必须为正数且不超过当前剩余库存，违反时抛 StateError（中文信息）。
  /// 返回扣减后的剩余数量。
  Future<int> consume({
    required int supplyId,
    required int deductCount,
    String? remark,
  }) async {
    if (deductCount <= 0) {
      throw StateError('领用数量必须大于 0');
    }
    final db = await _dbHelper.database;
    return db.transaction<int>((txn) async {
      // 事务内重读最新库存，避免并发下扣成负数
      final rows = await txn.query(
        'home_supply',
        columns: ['count'],
        where: 'id = ?',
        whereArgs: [supplyId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('物资不存在或已被删除');
      }
      final current = (rows.first['count'] as num?)?.toInt() ?? 1;
      if (deductCount > current) {
        throw StateError('领用数量不能超过当前库存（剩余 $current）');
      }
      // ① 扣减库存
      final remaining = current - deductCount;
      await txn.update(
        'home_supply',
        {'count': remaining},
        where: 'id = ?',
        whereArgs: [supplyId],
      );
      // ② 写入出库流水
      await txn.insert('consume_log', {
        'supplyId': supplyId,
        'deductCount': deductCount,
        'consumeTime': utcNow().toIso8601String(),
        'remark': remark,
      });
      return remaining;
    });
  }

  /// 全部出库流水（时间正序）——v1.8 统计页月度消耗趋势用
  Future<List<ConsumeLog>> listAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query('consume_log', orderBy: 'consumeTime ASC, id ASC');
    return rows.map(ConsumeLog.fromMap).toList();
  }

  /// 某物资的全部出库流水（时间倒序），仅查阅用
  Future<List<ConsumeLog>> listBySupply(int supplyId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'consume_log',
      where: 'supplyId = ?',
      whereArgs: [supplyId],
      orderBy: 'consumeTime DESC, id DESC',
    );
    return rows.map(ConsumeLog.fromMap).toList();
  }

  /// 某物资的累计出库数量（详情页汇总展示用）
  Future<int> totalConsumed(int supplyId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT IFNULL(SUM(deductCount), 0) AS total FROM consume_log WHERE supplyId = ?',
      [supplyId],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }
}

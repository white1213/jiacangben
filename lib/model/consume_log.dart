import '../utils/date_utils.dart';
import '../utils/json_utils.dart';

/// v1.4：物资领用出库流水（只针对消耗物资出库；流水不可编辑、不可删除）
class ConsumeLog {
  int? id;
  int supplyId; // 关联 home_supply.id
  int deductCount; // 本次扣减领用数量（正数）
  DateTime consumeTime; // UTC
  String? remark; // 备注：吃掉 / 过期丢弃 / 使用完毕等

  ConsumeLog({
    this.id,
    required this.supplyId,
    required this.deductCount,
    required this.consumeTime,
    this.remark,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'supplyId': supplyId,
        'deductCount': deductCount,
        'consumeTime': consumeTime.toUtc().toIso8601String(),
        'remark': remark,
      };

  factory ConsumeLog.fromMap(Map<String, Object?> map) => ConsumeLog(
        id: asInt(map['id']),
        supplyId: asInt(map['supplyId']) ?? 0,
        // 宽松解析：备份导入时字段可能为 double/String 形态
        deductCount: asInt(map['deductCount']) ?? 0,
        consumeTime: parseUtc(map['consumeTime'] as String?) ?? utcNow(),
        remark: map['remark'] as String?,
      );
}

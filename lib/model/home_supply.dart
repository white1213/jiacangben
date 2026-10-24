import '../utils/date_utils.dart';
import '../utils/json_utils.dart';

/// 保质期时长单位
enum ShelfUnit {
  day._('天'),
  month._('月'),
  year._('年');

  const ShelfUnit._(this.label);
  final String label;

  static ShelfUnit? fromName(String? name) =>
      name == null ? null : ShelfUnit.values.asNameMap()[name];
}

/// 消耗物资（食品 / 护肤品 / 日化用品 保质期台账）
///
/// 所有 DateTime 一律以 UTC 存入数据库（TEXT ISO8601），界面展示时转本地时区。
class HomeSupply {
  int? id;
  String name;
  DateTime purchaseDate; // 购入日期（UTC）
  DateTime expireDate; // 外包装到期日期（UTC）
  bool isOpened; // 是否开封
  DateTime? openDate; // 开封日期（UTC）
  int? afterOpenDays; // 开封后建议使用天数，可为 null
  int? categoryId; // v1.1：归属分类 item_category.id，可为 null
  int count; // v1.4：当前库存数量（领用出库时扣减）
  DateTime? productionDate; // v1.5：生产日期（UTC，算式录入；直接选日期/旧数据为 null）
  int? shelfValue; // v1.5：保质期时长数值（算式录入）
  ShelfUnit? shelfUnit; // v1.5：保质期时长单位（算式录入）
  String? note;

  HomeSupply({
    this.id,
    required this.name,
    required this.purchaseDate,
    required this.expireDate,
    this.isOpened = false,
    this.openDate,
    this.afterOpenDays,
    this.categoryId,
    this.count = 1,
    this.productionDate,
    this.shelfValue,
    this.shelfUnit,
    this.note,
  });

  /// 开封到期是否有效：已开封且开封日期、天数齐全
  bool get hasOpenExpire => isOpened && openDate != null && afterOpenDays != null;

  /// v1.5：是否按「生产日期 + 保质期时长」算式录入
  bool get hasShelfFormula => productionDate != null && shelfValue != null && shelfUnit != null;

  /// v1.5：按算式计算到期日 = 生产日期 + 时长（天/日历月/日历年，月末自动钳制）。
  /// 仅供录入/编辑页生成 expireDate；状态计算仍以库中 expireDate 列为准。
  DateTime computeExpireDate() {
    final base = productionDate!;
    final value = shelfValue!;
    switch (shelfUnit!) {
      case ShelfUnit.day:
        return base.add(Duration(days: value));
      case ShelfUnit.month:
        return _addCalendarMonths(base, value);
      case ShelfUnit.year:
        return _addCalendarMonths(base, value * 12);
    }
  }

  /// 日历月加法：月数进位，日超过目标月天数时钳制到月末（如 1-31 + 1月 = 2-28/29）。
  /// 结果与 base 保持相同时区形态与时刻分量（页面传本地时区日期，避免跨零点时区导致日期偏移）
  static DateTime _addCalendarMonths(DateTime base, int months) {
    final total = base.year * 12 + (base.month - 1) + months;
    final year = total ~/ 12;
    final month = total % 12 + 1;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final day = base.day <= daysInMonth ? base.day : daysInMonth;
    return base.isUtc
        ? DateTime.utc(year, month, day, base.hour, base.minute, base.second,
            base.millisecond, base.microsecond)
        : DateTime(year, month, day, base.hour, base.minute, base.second,
            base.millisecond, base.microsecond);
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'purchaseDate': purchaseDate.toUtc().toIso8601String(),
        'expireDate': expireDate.toUtc().toIso8601String(),
        'isOpened': isOpened ? 1 : 0,
        'openDate': toUtcIsoString(openDate),
        'afterOpenDays': afterOpenDays,
        'categoryId': categoryId,
        'count': count,
        'productionDate': toUtcIsoString(productionDate),
        'shelfValue': shelfValue,
        'shelfUnit': shelfUnit?.name,
        'note': note,
      };

  factory HomeSupply.fromMap(Map<String, Object?> map) => HomeSupply(
        // json_utils 宽松转换：兼容导入备份中 num/double/String 形态的整数字段
        id: asInt(map['id']),
        name: map['name'] as String,
        purchaseDate: DateTime.parse(map['purchaseDate'] as String).toUtc(),
        expireDate: DateTime.parse(map['expireDate'] as String).toUtc(),
        isOpened: map['isOpened'] == 1 || map['isOpened'] == true,
        openDate: parseUtc(map['openDate'] as String?),
        afterOpenDays: asInt(map['afterOpenDays']),
        categoryId: asInt(map['categoryId']),
        count: asInt(map['count']) ?? 1, // 旧数据/旧备份无该列时默认 1
        // v1.5：旧备份无这三列时为 null（直接选日期语义）
        productionDate: parseUtc(map['productionDate'] as String?),
        shelfValue: asInt(map['shelfValue']),
        shelfUnit: ShelfUnit.fromName(map['shelfUnit'] as String?),
        note: map['note'] as String?,
      );
}

import '../utils/date_utils.dart';

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
  String? note;

  HomeSupply({
    this.id,
    required this.name,
    required this.purchaseDate,
    required this.expireDate,
    this.isOpened = false,
    this.openDate,
    this.afterOpenDays,
    this.note,
  });

  /// 开封到期是否有效：已开封且开封日期、天数齐全
  bool get hasOpenExpire => isOpened && openDate != null && afterOpenDays != null;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'purchaseDate': purchaseDate.toUtc().toIso8601String(),
        'expireDate': expireDate.toUtc().toIso8601String(),
        'isOpened': isOpened ? 1 : 0,
        'openDate': toUtcIsoString(openDate),
        'afterOpenDays': afterOpenDays,
        'note': note,
      };

  factory HomeSupply.fromMap(Map<String, Object?> map) => HomeSupply(
        id: map['id'] as int?,
        name: map['name'] as String,
        purchaseDate: DateTime.parse(map['purchaseDate'] as String).toUtc(),
        expireDate: DateTime.parse(map['expireDate'] as String).toUtc(),
        isOpened: map['isOpened'] == 1 || map['isOpened'] == true,
        openDate: parseUtc(map['openDate'] as String?),
        afterOpenDays: map['afterOpenDays'] == null ? null : (map['afterOpenDays'] as num).toInt(),
        note: map['note'] as String?,
      );
}

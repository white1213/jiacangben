/// v1.1 新增：分类（区分消耗物资分类 / 普通物件分类）
class ItemCategory {
  static const String targetTypeSupply = 'supply';
  static const String targetTypeThing = 'thing';

  int? id;
  String name;
  String targetType; // "supply" / "thing"
  String? note;

  ItemCategory({this.id, required this.name, required this.targetType, this.note});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'targetType': targetType,
        'note': note,
      };

  factory ItemCategory.fromMap(Map<String, Object?> map) => ItemCategory(
        id: map['id'] as int?,
        name: map['name'] as String,
        targetType: map['targetType'] as String,
        note: map['note'] as String?,
      );
}

/// 普通收纳物件
import '../utils/json_utils.dart';

class StoredItem {
  int? id;
  String name;
  int count;
  int? locationId; // 外键 storage_location.id，允许 null（未归位）
  int? categoryId; // v1.1：归属分类 item_category.id，允许 null
  String? note;

  StoredItem({this.id, required this.name, this.count = 1, this.locationId, this.categoryId, this.note});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'count': count,
        'locationId': locationId,
        'categoryId': categoryId,
        'note': note,
      };

  factory StoredItem.fromMap(Map<String, Object?> map) => StoredItem(
        id: asInt(map['id']),
        name: map['name'] as String,
        count: asInt(map['count']) ?? 1,
        locationId: asInt(map['locationId']),
        categoryId: asInt(map['categoryId']),
        note: map['note'] as String?,
      );
}

/// 普通收纳物件
class StoredItem {
  int? id;
  String name;
  int count;
  int? locationId; // 外键 storage_location.id，允许 null（未归位）
  String? note;

  StoredItem({this.id, required this.name, this.count = 1, this.locationId, this.note});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'count': count,
        'locationId': locationId,
        'note': note,
      };

  factory StoredItem.fromMap(Map<String, Object?> map) => StoredItem(
        id: map['id'] as int?,
        name: map['name'] as String,
        count: (map['count'] as num?)?.toInt() ?? 1,
        locationId: map['locationId'] as int?,
        note: map['note'] as String?,
      );
}

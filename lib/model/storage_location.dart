/// 收纳位置（柜子、抽屉、储物箱）
class StorageLocation {
  int? id;
  String name;
  String? description;

  StorageLocation({this.id, required this.name, this.description});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'description': description,
      };

  factory StorageLocation.fromMap(Map<String, Object?> map) => StorageLocation(
        id: map['id'] as int?,
        name: map['name'] as String,
        description: map['description'] as String?,
      );
}

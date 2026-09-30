/// 标签归属关系
class TagRelation {
  static const String ownerTypeSupply = 'supply';
  static const String ownerTypeStoredItem = 'storedItem';

  int? id;
  String ownerType; // "supply" / "storedItem"
  int ownerId;
  int tagId;

  TagRelation({this.id, required this.ownerType, required this.ownerId, required this.tagId});

  Map<String, Object?> toMap() => {
        'id': id,
        'ownerType': ownerType,
        'ownerId': ownerId,
        'tagId': tagId,
      };

  factory TagRelation.fromMap(Map<String, Object?> map) => TagRelation(
        id: map['id'] as int?,
        ownerType: map['ownerType'] as String,
        ownerId: (map['ownerId'] as num).toInt(),
        tagId: (map['tagId'] as num).toInt(),
      );
}

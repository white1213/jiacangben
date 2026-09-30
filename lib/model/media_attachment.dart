/// v1.2：媒体附件（数据库仅存本地文件路径，禁止 BLOB 存图）
class MediaAttachment {
  static const String ownerTypeSupply = 'supply';
  static const String ownerTypeStoredItem = 'storedItem';
  static const String ownerTypeLocation = 'location';

  int? id;
  String ownerType; // "supply" / "storedItem" / "location"
  int ownerId;
  String localFilePath;
  DateTime createTime; // UTC

  MediaAttachment({
    this.id,
    required this.ownerType,
    required this.ownerId,
    required this.localFilePath,
    required this.createTime,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'ownerType': ownerType,
        'ownerId': ownerId,
        'localFilePath': localFilePath,
        'createTime': createTime.toUtc().toIso8601String(),
      };

  factory MediaAttachment.fromMap(Map<String, Object?> map) => MediaAttachment(
        id: map['id'] as int?,
        ownerType: map['ownerType'] as String,
        ownerId: (map['ownerId'] as num).toInt(),
        localFilePath: map['localFilePath'] as String,
        createTime: DateTime.parse(map['createTime'] as String).toUtc(),
      );
}

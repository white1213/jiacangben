/// 标签
class Tag {
  int? id;
  String name;

  Tag({this.id, required this.name});

  Map<String, Object?> toMap() => {'id': id, 'name': name};

  factory Tag.fromMap(Map<String, Object?> map) => Tag(
        id: map['id'] as int?,
        name: map['name'] as String,
      );
}

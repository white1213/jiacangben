/// v1.2：保存的筛选条件（JSON 存储）
import 'dart:convert';

class SavedFilter {
  static const String targetTypeSupply = 'supply';
  static const String targetTypeThing = 'thing';

  int? id;
  String name;
  String targetType;
  Map<String, dynamic> filterJson;

  SavedFilter({this.id, required this.name, required this.targetType, this.filterJson = const {}});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'targetType': targetType,
        'filterJson': filterJson.isEmpty ? null : jsonEncode(filterJson),
      };

  factory SavedFilter.fromMap(Map<String, Object?> map) => SavedFilter(
        id: map['id'] as int?,
        name: map['name'] as String,
        targetType: map['targetType'] as String,
        filterJson: _decode(map['filterJson']),
      );

  static Map<String, dynamic> _decode(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        // 损坏的 JSON 视为空筛选
      }
    }
    return {};
  }
}

/// v1.2：录入模板（预设表单字段，JSON 存储）
import 'dart:convert';

class EntryTemplate {
  static const String targetTypeSupply = 'supply';
  static const String targetTypeThing = 'thing';

  int? id;
  String name;
  String targetType; // "supply" / "thing"
  Map<String, dynamic> presetFields;

  EntryTemplate({this.id, required this.name, required this.targetType, this.presetFields = const {}});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'targetType': targetType,
        // JSON 文本存储，数据库层保持简单扁平结构
        'presetFields': presetFields.isEmpty ? null : jsonEncode(presetFields),
      };

  factory EntryTemplate.fromMap(Map<String, Object?> map) => EntryTemplate(
        id: map['id'] as int?,
        name: map['name'] as String,
        targetType: map['targetType'] as String,
        presetFields: _decode(map['presetFields']),
      );

  static Map<String, dynamic> _decode(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        // 损坏的 JSON 视为空模板，不影响列表展示
      }
    }
    return {};
  }
}

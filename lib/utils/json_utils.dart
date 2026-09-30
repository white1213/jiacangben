/// JSON 工具：备份导入时的宽松类型转换（JSON 反序列化后 num/String 与数据库 int/String 混用）
library;

import 'date_utils.dart';

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? asString(Object? value) => value is String ? value : null;

bool asBool(Object? value) {
  if (value is bool) return value;
  final v = asInt(value);
  return v == 1;
}

DateTime? asUtcDateTime(Object? value) => value is String ? parseUtc(value) : null;

/// 日期工具：数据库一律 UTC 存储，界面展示一律本地时区。
library;

import 'package:flutter/material.dart';

/// 当前 UTC 时间
DateTime utcNow() => DateTime.now().toUtc();

/// DateTime -> UTC ISO8601 字符串（null 安全）
String? toUtcIsoString(DateTime? dateTime) => dateTime?.toUtc().toIso8601String();

/// 字符串 -> UTC DateTime，空串/非法返回 null
DateTime? parseUtc(String? text) {
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text)?.toUtc();
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 本地时区 yyyy-MM-dd
String formatLocalDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

/// 本地时区 yyyy-MM-dd HH:mm
String formatLocalDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:${_two(local.minute)}';
}

/// 系统日期选择器；返回本地时区当日零点，入库时由 Model 统一转 UTC
Future<DateTime?> pickDate(BuildContext context, DateTime? initial) {
  return showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100, 12, 31),
  );
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../consts.dart';
import '../model/list_filter.dart';

/// 轻量设置项持久化（shared_preferences，不建数据库表）
class SettingsService {
  static const String _keyWarnDays = 'expiryWarnDays';
  static const String _keyActiveFilterPrefix = 'activeFilter_';

  /// 临期预警天数（默认 30）
  Future<int> getWarnDays() async {
    final prefs = await SharedPreferences.getInstance();
    final days = prefs.getInt(_keyWarnDays) ?? kExpiringSoonDays;
    // 防御：设置值被外部改坏时回退默认
    if (days < 1 || days > 365) return kExpiringSoonDays;
    return days;
  }

  Future<void> setWarnDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyWarnDays, days);
  }

  /// v1.3：读取某列表类型当前激活的筛选条件（null = 未筛选）。
  /// [targetType] 取 ItemCategory.targetType* 常量（supply / thing）。
  Future<ListFilter?> getActiveFilter(String targetType) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyActiveFilterPrefix$targetType');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ListFilter.fromJson(decoded.map((k, v) => MapEntry(k.toString(), v)));
      }
    } catch (_) {
      // 损坏数据视为未筛选
    }
    return null;
  }

  /// v1.3：保存/清除某列表类型当前激活的筛选条件（传 null 或空筛选即清除）
  Future<void> setActiveFilter(String targetType, ListFilter? filter) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyActiveFilterPrefix$targetType';
    if (filter == null || filter.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(filter.toJson()));
    }
  }
}

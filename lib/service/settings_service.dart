import 'package:shared_preferences/shared_preferences.dart';

import '../consts.dart';

/// 轻量设置项持久化（shared_preferences，不建数据库表）
class SettingsService {
  static const String _keyWarnDays = 'expiryWarnDays';

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
}

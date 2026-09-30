import 'package:flutter/material.dart';

/// 应用版本号（与 pubspec.yaml version 保持一致）
const String kAppVersion = '1.4.1';

/// 应用名
const String kAppName = '家藏本';

/// 数据库文件名
const String kDbName = 'jiacangben.db';

/// 临期判定阈值（天）：距离最终失效时间 <= 30 天视为临期
const int kExpiringSoonDays = 30;

/// 状态标签颜色：临期 黄
const Color kColorExpiringSoon = Color(0xFFF9D56E);

/// 状态标签颜色：已过期 红
const Color kColorExpired = Color(0xFFE55555);

/// 状态标签颜色：正常 灰
const Color kColorNormal = Color(0xFF949494);

/// 备份子目录名（位于应用文档目录下）
const String kBackupDirName = 'backups';

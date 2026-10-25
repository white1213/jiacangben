import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../database/supply_service.dart';
import '../model/home_supply.dart';
import '../service/expiry_service.dart';
import '../service/settings_service.dart';
import '../utils/date_utils.dart';

/// v1.6：临期桌面小部件——单行快照数据（原生侧按剩余毫秒现算「剩X天」，保证不打开 App 数字也不 stale）
class WidgetRow {
  final String name;
  final DateTime expire; // 最终失效时间（含开封提前到期）
  final bool expired;

  const WidgetRow({required this.name, required this.expire, required this.expired});

  Map<String, Object?> toJson() =>
      {'n': name, 'e': expire.millisecondsSinceEpoch, 'x': expired ? 1 : 0};
}

const String kWidgetRowsKey = 'jiacangben_expiring_rows';
const int kWidgetRowLimit = 5;

/// 纯函数：过期置顶 + 临期（[warnDays] 口径，与 App 内一致），按失效时间升序取最近 [limit] 条。
/// 过期的失效时间最早，升序排序天然让红牌置顶。
List<WidgetRow> buildWidgetRows(
  List<HomeSupply> supplies, {
  required int warnDays,
  DateTime? now,
  int limit = kWidgetRowLimit,
}) {
  final n = now ?? utcNow();
  final urgent = <({HomeSupply supply, DateTime expire, bool expired})>[];
  for (final s in supplies) {
    final status = ExpiryService.statusOf(s, now: n, warnDays: warnDays);
    if (status == ExpiryStatus.normal) continue;
    urgent.add((
      supply: s,
      expire: ExpiryService.finalExpireDate(s),
      expired: status == ExpiryStatus.expired,
    ));
  }
  urgent.sort((a, b) => a.expire.compareTo(b.expire));
  return urgent
      .take(limit)
      .map((e) => WidgetRow(name: e.supply.name, expire: e.expire, expired: e.expired))
      .toList();
}

/// 小部件数据刷新：查库 → 构建快照 → 写入 home_widget 共享存储 → 触发原生重绘。
/// 调用时机：App 启动 / 回前台（main.dart 生命周期挂钩）；原生侧另有 30 分钟系统周期重绘。
class WidgetService {
  Future<void> refresh() async {
    final warnDays = await SettingsService().getWarnDays();
    final supplies = await SupplyService().listAll();
    final rows = buildWidgetRows(supplies, warnDays: warnDays);
    await HomeWidget.saveWidgetData(
      kWidgetRowsKey,
      jsonEncode(rows.map((r) => r.toJson()).toList()),
    );
    await HomeWidget.updateWidget(androidName: 'ExpiringWidgetProvider');
  }
}

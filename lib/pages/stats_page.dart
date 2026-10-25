import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../consts.dart';
import '../database/category_service.dart';
import '../database/consume_log_service.dart';
import '../database/item_service.dart';
import '../database/location_service.dart';
import '../database/supply_service.dart';
import '../model/item_category.dart';
import '../service/expiry_service.dart';
import '../service/settings_service.dart';
import 'supply_list_page.dart';

/// v1.8：统计页——分类占比 / 临期状态分布 / 月度消耗趋势 / 物件位置分布。
/// 图表静态展示（不做缩放拖动），每区块给「查看列表」直达入口。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _loading = true;

  // 分类占比
  final Map<String, int> _categoryCounts = {}; // 名称 -> 件数（含「未分类」）
  // 临期状态分布
  int _normal = 0, _expiring = 0, _expired = 0;
  // 月度消耗趋势（近 6 个月，本地时区年月）
  final List<(String, int)> _monthly = []; // (yyyy-MM, 合计扣减)
  // 位置分布
  final Map<String, int> _locationCounts = {}; // 名称 -> 件数（含「未指定位置」）

  /// 分类环图配色（棕系主题往外扩的协调色板，超出数量循环取）
  static const _palette = [
    Color(0xFF8D6E63), Color(0xFFA1887F), Color(0xFFBCAAA4),
    Color(0xFFD7CCC8), Color(0xFF6D4C41), Color(0xFF5D4037),
    Color(0xFF8A6D00), Color(0xFFF9D56E),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final warnDays = await SettingsService().getWarnDays();
    final supplies = await SupplyService().listAll();
    final categories = await CategoryService().listAll(targetType: ItemCategory.targetTypeSupply);
    final logs = await ConsumeLogService().listAll();
    final locations = await LocationService().listAll();
    final itemLocationIds = await ItemService().listAll();

    // 1) 分类占比
    final catNameById = {for (final c in categories) c.id: c.name};
    final byCat = <String, int>{};
    for (final s in supplies) {
      final label = catNameById[s.categoryId] ?? '未分类';
      byCat[label] = (byCat[label] ?? 0) + s.count;
    }
    // 2) 临期状态分布
    var normal = 0, expiring = 0, expired = 0;
    for (final s in supplies) {
      switch (ExpiryService.statusOf(s, warnDays: warnDays)) {
        case ExpiryStatus.normal:
          normal++;
        case ExpiryStatus.expiringSoon:
          expiring++;
        case ExpiryStatus.expired:
          expired++;
      }
    }
    // 3) 月度消耗趋势（近 6 个月，含空月）
    final now = DateTime.now();
    final months = List.generate(6, (i) => DateTime(now.year, now.month - 5 + i));
    final monthKeys = [for (final m in months) '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}'];
    final byMonth = {for (final k in monthKeys) k: 0};
    for (final log in logs) {
      final local = log.consumeTime.toLocal();
      final key = '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}';
      if (byMonth.containsKey(key)) byMonth[key] = byMonth[key]! + log.deductCount;
    }
    // 4) 物件位置分布
    final locNameById = {for (final l in locations) l.id: l.name};
    final byLoc = <String, int>{};
    for (final item in itemLocationIds) {
      final label = item.locationId == null ? '未指定位置' : (locNameById[item.locationId] ?? '未知位置');
      byLoc[label] = (byLoc[label] ?? 0) + item.count;
    }

    if (!mounted) return;
    setState(() {
      _categoryCounts
        ..clear()
        ..addAll(byCat);
      _normal = normal;
      _expiring = expiring;
      _expired = expired;
      _monthly
        ..clear()
        ..addAll([for (final k in monthKeys) (k, byMonth[k]!)]);
      _locationCounts
        ..clear()
        ..addAll(byLoc);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _section(
                  '物资分类占比（按库存件数）',
                  _categoryCounts.isEmpty ? _empty('还没有消耗物资') : _categoryPie(),
                  onView: () => _openList(const HomeSupplyListPage()),
                ),
                _section(
                  '临期状态分布（按种类数）',
                  _statusPie(),
                  onView: () => _openList(const HomeSupplyListPage(initialFilter: SupplyStatusFilter.urgent)),
                ),
                _section('近 6 个月领用消耗（件）', _monthlyBars()),
                _section(
                  '物件位置分布（按件数）',
                  _locationCounts.isEmpty ? _empty('还没有收纳物件') : _locationPie(),
                ),
              ],
            ),
    );
  }

  void _openList(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _section(String title, Widget chart, {VoidCallback? onView}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                if (onView != null)
                  TextButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.list_alt_outlined, size: 16),
                    label: const Text('查看列表'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            chart,
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(text, style: TextStyle(color: Colors.grey.shade500))),
      );

  /// 通用环图（数据非空时调用）
  Widget _donut(List<(String, int, Color)> slices) {
    final total = slices.fold<int>(0, (a, s) => a + s.$2);
    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 44,
                sections: [
                  for (var i = 0; i < slices.length; i++)
                    PieChartSectionData(
                      value: slices[i].$2.toDouble(),
                      color: slices[i].$3,
                      radius: 16,
                      title: slices[i].$2.toString(),
                      titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (name, value, color) in slices.take(7))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$name $value',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (slices.length > 7)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('共 $total 件 · ${slices.length} 类', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryPie() {
    final entries = _categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _donut([
      for (var i = 0; i < entries.length; i++)
        (entries[i].key, entries[i].value, _palette[i % _palette.length]),
    ]);
  }

  Widget _statusPie() {
    if (_normal + _expiring + _expired == 0) return _empty('还没有消耗物资');
    return _donut([
      ('过期', _expired, kColorExpired),
      ('临期', _expiring, kColorExpiringSoon),
      ('正常', _normal, kColorNormal),
    ]);
  }

  Widget _locationPie() {
    final entries = _locationCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _donut([
      for (var i = 0; i < entries.length; i++)
        (entries[i].key, entries[i].value, _palette[i % _palette.length]),
    ]);
  }

  Widget _monthlyBars() {
    final hasData = _monthly.any((m) => m.$2 > 0);
    if (!hasData) return _empty('还没有领用出库记录');
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= _monthly.length) return const SizedBox.shrink();
                  final ym = _monthly[i].$1; // yyyy-MM → 只显 MM 月
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${ym.substring(5)}月', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < _monthly.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: _monthly[i].$2.toDouble(),
                    width: 22,
                    borderRadius: BorderRadius.circular(4),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

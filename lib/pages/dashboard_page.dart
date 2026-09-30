import 'package:flutter/material.dart';

import '../consts.dart';
import '../database/item_service.dart';
import '../database/location_service.dart';
import '../database/supply_service.dart';
import '../model/home_supply.dart';
import '../model/storage_location.dart';
import '../model/stored_item.dart';
import '../service/expiry_service.dart';
import '../service/settings_service.dart';
import '../utils/date_utils.dart';
import 'category_manage_page.dart';
import 'edit/item_edit_page.dart';
import 'edit/supply_edit_page.dart';
import 'backup_restore_page.dart';
import 'item_list_page.dart';
import 'location_list_page.dart';
import 'settings_page.dart';
import 'supply_list_page.dart';
import 'tag_manage_page.dart';
import 'template_manage_page.dart';

/// 首页仪表盘（启动页）
class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({super.key});

  @override
  State<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends State<HomeDashboardPage> {
  final SupplyService _supplyService = SupplyService();
  final ItemService _itemService = ItemService();
  final LocationService _locationService = LocationService();

  bool _loading = true;
  List<HomeSupply> _supplies = const [];
  List<StoredItem> _items = const [];
  List<StorageLocation> _locations = const [];
  Map<int, String> _locationNames = const {};

  int _searchSeq = 0;
  String _query = '';
  List<HomeSupply> _supplyHits = const [];
  List<StoredItem> _itemHits = const [];
  int _warnDays = kExpiringSoonDays; // 设置页可自定义的临期预警天数

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final warnDays = await SettingsService().getWarnDays();
    final supplies = await _supplyService.listAll();
    final items = await _itemService.listAll();
    final locations = await _locationService.listAll();
    if (!mounted) return;
    setState(() {
      _supplies = supplies;
      _items = items;
      _locations = locations;
      _warnDays = warnDays;
      _locationNames = {
        for (final l in locations)
          if (l.id != null) l.id!: l.name,
      };
      _loading = false;
    });
    _runSearch(_query);
  }

  /// 前台内存扫描：仅在本页加载 / 从子页返回时计算临期与过期，无任何后台任务
  List<HomeSupply> _scanWarnings() {
    final now = DateTime.now().toUtc();
    final list = _supplies
        .where((s) => ExpiryService.statusOf(s, now: now, warnDays: _warnDays) != ExpiryStatus.normal)
        .toList()
      ..sort((a, b) => ExpiryService.finalExpireDate(a).compareTo(ExpiryService.finalExpireDate(b)));
    return list;
  }

  Future<void> _runSearch(String keyword) async {
    final seq = ++_searchSeq;
    final kw = keyword.trim();
    if (kw.isEmpty) {
      setState(() {
        _query = keyword;
        _supplyHits = const [];
        _itemHits = const [];
      });
      return;
    }
    final supplyHits = await _supplyService.search(kw);
    final itemHits = await _itemService.search(kw);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _query = keyword;
      _supplyHits = supplyHits;
      _itemHits = itemHits;
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final warnings = _scanWarnings();
    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        actions: [
          // 设置入口（临期预警天数 / 关于）
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => _open(const SettingsPage()),
          ),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TextField(
                  onChanged: _runSearch,
                  decoration: const InputDecoration(
                    hintText: '搜索物资 / 物件（名称、备注）',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                if (searching)
                  ..._buildSearchSection()
                else ...[
                  _buildStatGrid(warnings.length),
                  const SizedBox(height: 12),
                  _buildWarningSection(warnings),
                  const SizedBox(height: 12),
                  _buildEntryGrid(),
                ],
              ],
            ),
    );
  }

  Widget _buildStatGrid(int warningCount) {
    Widget card(String label, int value, {Color? valueColor}) {
      return Card(
        margin: const EdgeInsets.all(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      children: [
        card('消耗物资总数', _supplies.length),
        card('临期 + 过期', warningCount, valueColor: warningCount > 0 ? kColorExpired : null),
        card('普通物件总数', _items.length),
        card('收纳位置总数', _locations.length),
      ],
    );
  }

  Widget _buildWarningSection(List<HomeSupply> warnings) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 8, bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: kColorExpired, size: 18),
                  const SizedBox(width: 6),
                  Text('临期 / 过期预警', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: 6),
                  Text(
                    '${warnings.length}',
                    style: const TextStyle(color: kColorExpired, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (warnings.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('暂无临期或过期物资', style: TextStyle(color: Colors.grey)),
              )
            else
              for (final s in warnings)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${formatLocalDate(ExpiryService.finalExpireDate(s))} · ${ExpiryService.describeLeft(s)}',
                  ),
                  trailing: StatusChip(status: ExpiryService.statusOf(s)),
                  onTap: () => _open(SupplyEditPage(supply: s)),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryGrid() {
    Widget entry(IconData icon, String label, VoidCallback onTap) {
      return Card(
        margin: const EdgeInsets.all(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 30),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.0,
      children: [
        entry(Icons.kitchen, '消耗物资库', () => _open(const HomeSupplyListPage())),
        entry(Icons.inventory_2, '收纳位置管理', () => _open(const StorageLocationListPage())),
        entry(Icons.category_outlined, '全部物件', () => _open(const StoredItemListPage())),
        entry(Icons.settings_backup_restore, '备份与恢复', () => _open(const BackupRestorePage())),
        // v1.1 新增入口
        entry(Icons.category, '分类管理', () => _open(const CategoryManagePage())),
        entry(Icons.label_outline, '标签管理', () => _open(const TagManagePage())),
        // v1.2 新增入口
        entry(Icons.playlist_add_check, '录入模板', () => _open(const TemplateManagePage())),
      ],
    );
  }

  List<Widget> _buildSearchSection() {
    Widget header(String text) => Padding(
          padding: const EdgeInsets.only(left: 16, top: 10, bottom: 2),
          child: Text(text, style: Theme.of(context).textTheme.titleSmall),
        );

    final children = <Widget>[
      if (_supplyHits.isNotEmpty) ...[
        header('消耗物资（${_supplyHits.length}）'),
        for (final s in _supplyHits)
          ListTile(
            dense: true,
            leading: const Icon(Icons.kitchen, size: 20),
            title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '失效：${formatLocalDate(ExpiryService.finalExpireDate(s))}'
              '${s.note == null || s.note!.isEmpty ? '' : ' · ${s.note}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: StatusChip(status: ExpiryService.statusOf(s)),
            onTap: () => _open(SupplyEditPage(supply: s)),
          ),
      ],
      if (_itemHits.isNotEmpty) ...[
        header('普通物件（${_itemHits.length}）'),
        for (final i in _itemHits)
          ListTile(
            dense: true,
            leading: const Icon(Icons.category_outlined, size: 20),
            title: Text('${i.name} ×${i.count}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '位置：${i.locationId == null ? '未归位' : (_locationNames[i.locationId] ?? '未知')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _open(ItemEditPage(item: i)),
          ),
      ],
    ];

    if (children.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '未找到与「${_query.trim()}」匹配的物资或物件',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ];
    }
    return [Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children))];
  }
}

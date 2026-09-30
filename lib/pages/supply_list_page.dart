import 'package:flutter/material.dart';

import '../consts.dart';
import '../database/supply_service.dart';
import '../database/tag_service.dart';
import '../model/home_supply.dart';
import '../model/tag.dart';
import '../model/tag_relation.dart';
import '../service/expiry_service.dart';
import '../utils/date_utils.dart';
import 'edit/supply_edit_page.dart';

/// 到期状态标签（颜色规范见 consts.dart）
class StatusChip extends StatelessWidget {
  final ExpiryStatus status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, textColor) = switch (status) {
      ExpiryStatus.expired => ('已过期', kColorExpired, Colors.white),
      ExpiryStatus.expiringSoon => ('临期', kColorExpiringSoon, const Color(0xFF4A3B00)),
      ExpiryStatus.normal => ('正常', kColorNormal, Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(color: textColor, fontSize: 11)),
    );
  }
}

/// 列表中的小标签
class MiniTagChip extends StatelessWidget {
  final String label;

  const MiniTagChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade700)),
    );
  }
}

enum _SupplyFilter { all, expiringSoon, expired }

/// 消耗物资列表页
class HomeSupplyListPage extends StatefulWidget {
  const HomeSupplyListPage({super.key});

  @override
  State<HomeSupplyListPage> createState() => _HomeSupplyListPageState();
}

class _HomeSupplyListPageState extends State<HomeSupplyListPage> {
  final SupplyService _service = SupplyService();
  final TagService _tagService = TagService();

  bool _loading = true;
  List<HomeSupply> _supplies = const [];
  Map<int, List<Tag>> _tagsByOwner = const {};
  _SupplyFilter _filter = _SupplyFilter.all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final supplies = await _service.listAll();
    final tags = await _tagService.tagsByOwner(TagRelation.ownerTypeSupply);
    supplies.sort((a, b) => ExpiryService.finalExpireDate(a).compareTo(ExpiryService.finalExpireDate(b)));
    if (!mounted) return;
    setState(() {
      _supplies = supplies;
      _tagsByOwner = tags;
      _loading = false;
    });
  }

  List<HomeSupply> get _filtered {
    switch (_filter) {
      case _SupplyFilter.all:
        return _supplies;
      case _SupplyFilter.expiringSoon:
        return _supplies.where((s) => ExpiryService.statusOf(s) == ExpiryStatus.expiringSoon).toList();
      case _SupplyFilter.expired:
        return _supplies.where((s) => ExpiryService.statusOf(s) == ExpiryStatus.expired).toList();
    }
  }

  Future<void> _openEditor([HomeSupply? supply]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplyEditPage(supply: supply)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('消耗物资库')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增物资'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<_SupplyFilter>(
              segments: const [
                ButtonSegment(value: _SupplyFilter.all, label: Text('全部')),
                ButtonSegment(value: _SupplyFilter.expiringSoon, label: Text('临期')),
                ButtonSegment(value: _SupplyFilter.expired, label: Text('已过期')),
              ],
              selected: {_filter},
              onSelectionChanged: (selection) => setState(() => _filter = selection.first),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const Center(child: Text('暂无物资记录', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                        itemCount: list.length,
                        itemBuilder: (_, index) => _buildCard(list[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(HomeSupply supply) {
    final status = ExpiryService.statusOf(supply);
    final tags = _tagsByOwner[supply.id] ?? const <Tag>[];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(supply.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            StatusChip(status: status),
            for (final tag in tags) MiniTagChip(label: tag.name),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '失效：${formatLocalDate(ExpiryService.finalExpireDate(supply))}（${ExpiryService.describeLeft(supply)}）\n'
            '购入：${formatLocalDate(supply.purchaseDate)}${supply.isOpened ? ' · 已开封' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        isThreeLine: true,
        onTap: () => _openEditor(supply),
      ),
    );
  }
}

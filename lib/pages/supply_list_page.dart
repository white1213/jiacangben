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
/// v1.1 新增：多选批量操作（批量标记已开封 / 批量删除）
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

  // v1.1 多选模式
  bool _selectMode = false;
  Set<int> _selectedIds = {};

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

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor([HomeSupply? supply]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplyEditPage(supply: supply)));
    await _reload();
  }

  void _toggleSelect(int? id) {
    if (id == null) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectMode = false;
    });
  }

  void _enterSelectMode(int? id) {
    setState(() {
      _selectMode = true;
      if (id != null) _selectedIds.add(id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds = {};
    });
  }

  /// v1.1：批量标记为已开封（开封日期记为今天）
  Future<void> _batchMarkOpened() async {
    if (_selectedIds.isEmpty) return;
    final marked = await _service.batchMarkOpened(_selectedIds.toList());
    _exitSelectMode();
    await _reload();
    if (!mounted) return;
    _snack(marked > 0 ? '已将 $marked 条物资标记为已开封（开封日期今天）' : '所选物资均已开封，无变更');
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 $count 条物资吗？该操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: kColorExpired),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await _service.batchDelete(_selectedIds.toList());
    _exitSelectMode();
    await _reload();
    if (mounted) _snack('已删除 $deleted 条物资');
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: _selectMode ? _buildSelectionAppBar() : AppBar(title: const Text('消耗物资库')),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('新增物资'),
            ),
      bottomNavigationBar: _selectMode ? _buildBatchBar() : null,
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

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectMode),
      title: Text('已选 ${_selectedIds.length} 项'),
      actions: [
        TextButton(
          onPressed: () {
            final allIds = _filtered.map((s) => s.id).whereType<int>().toSet();
            setState(() {
              if (allIds.length == _selectedIds.length && allIds.every(_selectedIds.contains)) {
                _selectedIds = {};
              } else {
                _selectedIds = allIds;
              }
            });
          },
          child: Text(
            _filtered.length == _selectedIds.length && _selectedIds.isNotEmpty ? '取消全选' : '全选',
          ),
        ),
      ],
    );
  }

  Widget _buildBatchBar() {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 批量标记为已开封（开封日期记为今天）
          TextButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _batchMarkOpened,
            icon: const Icon(Icons.open_in_new),
            label: const Text('批量开封'),
          ),
          TextButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _batchDelete,
            icon: const Icon(Icons.delete_outline, color: kColorExpired),
            label: const Text('批量删除', style: TextStyle(color: kColorExpired)),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(HomeSupply supply) {
    final status = ExpiryService.statusOf(supply);
    final tags = _tagsByOwner[supply.id] ?? const <Tag>[];
    final selected = _selectedIds.contains(supply.id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: ListTile(
        leading: _selectMode
            ? Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
              )
            : null,
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
        onLongPress: () => _enterSelectMode(supply.id),
        onTap: () {
          if (_selectMode) {
            _toggleSelect(supply.id);
          } else {
            _openEditor(supply);
          }
        },
      ),
    );
  }
}

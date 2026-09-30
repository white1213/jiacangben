import 'package:flutter/material.dart';

import '../consts.dart';
import '../database/location_service.dart';
import '../model/storage_location.dart';
import 'edit/location_edit_page.dart';
import 'item_list_page.dart';

/// 收纳位置管理页
class StorageLocationListPage extends StatefulWidget {
  const StorageLocationListPage({super.key});

  @override
  State<StorageLocationListPage> createState() => _StorageLocationListPageState();
}

class _StorageLocationListPageState extends State<StorageLocationListPage> {
  final LocationService _service = LocationService();

  bool _loading = true;
  List<StorageLocation> _locations = const [];
  Map<int, int> _itemCounts = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final locations = await _service.listAll();
    final counts = await _service.itemCountsByLocation();
    if (!mounted) return;
    setState(() {
      _locations = locations;
      _itemCounts = counts;
      _loading = false;
    });
  }

  Future<void> _openEditor([StorageLocation? location]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LocationEditPage(location: location)));
    await _reload();
  }

  Future<void> _openDetail(StorageLocation location) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoredItemListPage(locationId: location.id, appBarTitle: location.name),
      ),
    );
    await _reload();
  }

  /// 删除收纳位置：必须显式二选其一，禁止静默级联删除
  Future<void> _confirmDelete(StorageLocation location) async {
    final count = _itemCounts[location.id] ?? 0;
    // 1 = 物件 locationId 置空后删除位置；2 = 连同物件一起删除；0/ null = 取消
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${location.name}」'),
        content: Text(count > 0 ? '该位置下有 $count 件物件，请选择删除方式：' : '该位置下没有物件，可直接删除。'),
        actions: [
          if (count > 0) ...[
            TextButton(
              onPressed: () => Navigator.pop(ctx, 1),
              child: const Text('物件改为未归位'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(foregroundColor: kColorExpired),
              onPressed: () => Navigator.pop(ctx, 2),
              child: const Text('连同物件一起删除'),
            ),
          ] else
            FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, 1),
              child: const Text('删除'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (choice == null || choice == 0 || !mounted) return;
    await _service.delete(location.id!, alsoDeleteItems: choice == 2);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收纳位置管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增位置'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _locations.isEmpty
              ? const Center(child: Text('暂无收纳位置', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: _locations.length,
                  itemBuilder: (_, index) => _buildCard(_locations[index]),
                ),
    );
  }

  Widget _buildCard(StorageLocation location) {
    final count = _itemCounts[location.id] ?? 0;
    final desc = location.description?.trim() ?? '';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.inventory_2),
        title: Text(location.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '$count 件物件${desc.isEmpty ? '' : ' · $desc'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: () => _openEditor(location),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: kColorExpired),
              tooltip: '删除',
              onPressed: () => _confirmDelete(location),
            ),
          ],
        ),
        onTap: () => _openDetail(location),
      ),
    );
  }
}

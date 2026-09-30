import 'package:flutter/material.dart';

import '../database/item_service.dart';
import '../database/location_service.dart';
import '../database/tag_service.dart';
import '../model/stored_item.dart';
import '../model/tag.dart';
import '../model/tag_relation.dart';
import 'edit/item_edit_page.dart';
import 'supply_list_page.dart' show MiniTagChip;

/// 全部普通物件列表页（传 [locationId] 时为某收纳位置详情）
class StoredItemListPage extends StatefulWidget {
  final int? locationId;
  final String? appBarTitle;

  const StoredItemListPage({super.key, this.locationId, this.appBarTitle});

  @override
  State<StoredItemListPage> createState() => _StoredItemListPageState();
}

class _StoredItemListPageState extends State<StoredItemListPage> {
  final ItemService _itemService = ItemService();
  final LocationService _locationService = LocationService();
  final TagService _tagService = TagService();

  bool _loading = true;
  List<StoredItem> _items = const [];
  Map<int, String> _locationNames = const {};
  Map<int, List<Tag>> _tagsByOwner = const {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = widget.locationId == null
        ? await _itemService.listAll()
        : await _itemService.listByLocation(widget.locationId!);
    final locations = await _locationService.listAll();
    final tags = await _tagService.tagsByOwner(TagRelation.ownerTypeStoredItem);
    if (!mounted) return;
    setState(() {
      _items = items;
      _locationNames = {
        for (final l in locations)
          if (l.id != null) l.id!: l.name,
      };
      _tagsByOwner = tags;
      _loading = false;
    });
  }

  List<StoredItem> get _filtered {
    final kw = _query.trim();
    if (kw.isEmpty) return _items;
    return _items.where((i) => i.name.contains(kw) || (i.note ?? '').contains(kw)).toList();
  }

  Future<void> _openEditor([StoredItem? item]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ItemEditPage(item: item, presetLocationId: widget.locationId),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(title: Text(widget.appBarTitle ?? '全部物件')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增物件'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: '搜索物件（名称、备注）',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Text(
                          _query.trim().isEmpty ? '暂无物件' : '未找到匹配的物件',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
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

  Widget _buildCard(StoredItem item) {
    final tags = _tagsByOwner[item.id] ?? const <Tag>[];
    final location = item.locationId == null ? '未归位' : (_locationNames[item.locationId] ?? '未知');
    final note = item.note?.trim() ?? '';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('×${item.count}', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            for (final tag in tags) MiniTagChip(label: tag.name),
          ],
        ),
        subtitle: note.isEmpty ? Text('位置：$location') : Text('位置：$location · $note', maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => _openEditor(item),
      ),
    );
  }
}

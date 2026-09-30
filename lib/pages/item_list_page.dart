import 'package:flutter/material.dart';

import '../database/attachment_service.dart';
import '../database/item_service.dart';
import '../database/location_service.dart';
import '../database/tag_service.dart';
import '../model/media_attachment.dart';
import '../model/stored_item.dart';
import '../model/tag.dart';
import '../model/tag_relation.dart';
import 'edit/attachment_section.dart';
import 'edit/item_edit_page.dart';
import 'supply_list_page.dart' show MiniTagChip;

/// 全部普通物件列表页（传 [locationId] 时为某收纳位置详情）
/// v1.1 新增：多选批量操作（批量迁移收纳位置 / 批量删除）
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

  // v1.1 多选模式
  bool _selectMode = false;
  Set<int> _selectedIds = {};

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

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor([StoredItem? item]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ItemEditPage(item: item, presetLocationId: widget.locationId),
      ),
    );
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

  /// v1.1：批量迁移到目标收纳位置
  Future<void> _batchMove() async {
    if (_selectedIds.isEmpty) return;
    int? targetLocationId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('迁移 ${_selectedIds.length} 件物件'),
          content: DropdownButtonFormField<int?>(
            initialValue: targetLocationId,
            decoration: const InputDecoration(labelText: '目标收纳位置'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('未归位')),
              for (final entry in _locationNames.entries)
                DropdownMenuItem<int?>(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (v) => setDialogState(() => targetLocationId = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('迁移')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final moved = await _itemService.batchMove(_selectedIds.toList(), targetLocationId);
    _exitSelectMode();
    await _reload();
    if (mounted) _snack('已迁移 $moved 件物件到「${targetLocationId == null ? '未归位' : (_locationNames[targetLocationId] ?? '未知')}」');
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 $count 件物件吗？该操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: const Color(0xFFE55555)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ids = _selectedIds.toList();
    // v1.2：有关联图片时询问文件处理方式
    final cleanup = await confirmAttachmentCleanup(
      context,
      AttachmentService(),
      MediaAttachment.ownerTypeStoredItem,
      ids,
    );
    if (cleanup == AttachmentCleanup.cancel) return;
    if (cleanup != null) {
      await AttachmentService().purgeForOwners(
        MediaAttachment.ownerTypeStoredItem,
        ids,
        deleteFiles: cleanup == AttachmentCleanup.deleteFiles,
      );
    }
    final deleted = await _itemService.batchDelete(ids);
    _exitSelectMode();
    await _reload();
    if (mounted) _snack('已删除 $deleted 件物件');
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: _selectMode ? _buildSelectionAppBar() : AppBar(title: Text(widget.appBarTitle ?? '全部物件')),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('新增物件'),
            ),
      bottomNavigationBar: _selectMode ? _buildBatchBar() : null,
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

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectMode),
      title: Text('已选 ${_selectedIds.length} 件'),
      actions: [
        TextButton(
          onPressed: () {
            final allIds = _filtered.map((i) => i.id).whereType<int>().toSet();
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
          // 批量迁移到其他收纳位置
          TextButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _batchMove,
            icon: const Icon(Icons.drive_file_move_outline),
            label: const Text('批量迁移'),
          ),
          TextButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _batchDelete,
            icon: const Icon(Icons.delete_outline, color: Color(0xFFE55555)),
            label: const Text('批量删除', style: TextStyle(color: Color(0xFFE55555))),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(StoredItem item) {
    final tags = _tagsByOwner[item.id] ?? const <Tag>[];
    final location = item.locationId == null ? '未归位' : (_locationNames[item.locationId] ?? '未知');
    final note = item.note?.trim() ?? '';
    final selected = _selectedIds.contains(item.id);
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
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('×${item.count}', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            for (final tag in tags) MiniTagChip(label: tag.name),
          ],
        ),
        subtitle: note.isEmpty ? Text('位置：$location') : Text('位置：$location · $note', maxLines: 1, overflow: TextOverflow.ellipsis),
        onLongPress: () => _enterSelectMode(item.id),
        onTap: () {
          if (_selectMode) {
            _toggleSelect(item.id);
          } else {
            _openEditor(item);
          }
        },
      ),
    );
  }
}

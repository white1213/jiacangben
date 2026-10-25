import 'package:flutter/material.dart';

import '../database/attachment_service.dart';
import '../database/category_service.dart';
import '../database/item_service.dart';
import '../database/location_service.dart';
import '../database/tag_service.dart';
import '../model/item_category.dart';
import '../model/list_filter.dart';
import '../model/media_attachment.dart';
import '../model/stored_item.dart';
import '../model/tag.dart';
import '../model/tag_relation.dart';
import '../service/settings_service.dart';
import 'edit/attachment_section.dart';
import 'edit/item_edit_page.dart';
import 'filter_dialog.dart';
import 'supply_list_page.dart' show MiniTagChip;
import '../utils/list_sort.dart';

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

  // v1.3 分类 + 标签筛选（与文本搜索叠加）
  ListFilter _listFilter = ListFilter();
  List<ItemCategory> _categories = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// v1.3：进入页面还原上次激活的筛选条件（分类+标签），再加载列表
  Future<void> _init() async {
    final active = await SettingsService().getActiveFilter(ItemCategory.targetTypeThing);
    if (active != null && mounted) {
      setState(() => _listFilter = active);
    }
    await _reload();
  }

  Future<void> _reload() async {
    // v1.3：分类+标签筛选下沉到 SQL（tag_relation 子查询 OR 语义）；文本搜索保持内存过滤
    final items = widget.locationId == null
        ? await _itemService.listFiltered(categoryId: _listFilter.categoryId, tagIds: _listFilter.tagIds)
        : await _itemService.listByLocation(widget.locationId!);
    final locations = await _locationService.listAll();
    final tags = await _tagService.tagsByOwner(TagRelation.ownerTypeStoredItem);
    final categories = await CategoryService().listAll(targetType: ItemCategory.targetTypeThing);
    // v1.4：按当前排序配置排序（物件无到期时间项）
    sortStoredItems(items, _listFilter.sortBy);
    if (!mounted) return;
    setState(() {
      _items = items;
      _locationNames = {
        for (final l in locations)
          if (l.id != null) l.id!: l.name,
      };
      _tagsByOwner = tags;
      _categories = categories;
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

  /// v1.4：切换排序方式（与筛选、搜索叠加；持久化到激活筛选）
  Future<void> _changeSort(String sortBy) async {
    if (sortBy == _listFilter.sortBy) return;
    setState(() {
      _listFilter.sortBy = sortBy;
      // 排序仅影响展示顺序，直接对已加载数据重排即可
      sortStoredItems(_items, sortBy);
    });
    await SettingsService().setActiveFilter(ItemCategory.targetTypeThing, _listFilter);
  }

  /// v1.3：打开筛选弹窗（分类 + 标签），应用后持久化激活筛选并刷新
  Future<void> _showFilter() async {
    final tags = await _tagService.listAll();
    if (!mounted) return;
    final result = await showFilterDialog(
      context,
      categories: _categories,
      tags: tags,
      initialFilter: _listFilter,
      categoryTargetType: ItemCategory.targetTypeThing,
    );
    if (result == null || !mounted) return;
    setState(() => _listFilter = result.filter);
    await SettingsService().setActiveFilter(ItemCategory.targetTypeThing, _listFilter);
    await _reload();
  }

  /// 条目长按上下文菜单（编辑 / 多选 / 删除）
  Future<void> _showItemMenu(StoredItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('多选'),
              onTap: () => Navigator.pop(ctx, 'select'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: const Color(0xFFE55555)),
              title: const Text('删除', style: TextStyle(color: Color(0xFFE55555))),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _openEditor(item);
      case 'select':
        _enterSelectMode(item.id);
      case 'delete':
        await _deleteSingle(item);
    }
  }

  /// 单条删除（含关联图片处理确认）
  Future<void> _deleteSingle(StoredItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除物件'),
        content: Text('确定删除「${item.name}」吗？该操作不可撤销。'),
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
    if (ok != true || !mounted) return;
    final cleanup = await confirmAttachmentCleanup(
      context,
      AttachmentService(),
      MediaAttachment.ownerTypeStoredItem,
      [item.id!],
    );
    if (cleanup == AttachmentCleanup.cancel) return;
    if (cleanup != null) {
      await AttachmentService().purgeForOwners(
        MediaAttachment.ownerTypeStoredItem,
        [item.id!],
        deleteFiles: cleanup == AttachmentCleanup.deleteFiles,
      );
    }
    await _itemService.delete(item.id!);
    await _reload();
    if (mounted) _snack('已删除「${item.name}」');
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: _selectMode
          ? _buildSelectionAppBar()
          : AppBar(
              title: Text(widget.appBarTitle ?? '全部物件'),
              actions: [
                // v1.4：排序下拉（物件不显示到期时间项）
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  tooltip: '排序',
                  onSelected: _changeSort,
                  itemBuilder: (_) => [
                    for (final (key, label, supplyOnly) in kListSortOptions)
                      if (!supplyOnly)
                        CheckedPopupMenuItem<String>(
                          value: key,
                          checked: _listFilter.sortBy == key,
                          child: Text(label),
                        ),
                  ],
                ),
                // v1.3：筛选弹窗入口，激活时 Badge 高亮
                if (widget.locationId == null)
                  Badge(
                    isLabelVisible: _listFilter.isNotEmpty,
                    child: IconButton(
                      icon: const Icon(Icons.filter_alt),
                      tooltip: '筛选',
                      onPressed: _showFilter,
                    ),
                  ),
                // v1.3：多选批量操作入口（长按菜单之外的标准入口）
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: '多选',
                  onPressed: () => _enterSelectMode(null),
                ),
              ],
            ),
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
      // v1.8：卡片样式升级——大圆角 + 描边扁平风（与物资列表一致）
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      elevation: 0,
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
        onLongPress: () => _showItemMenu(item),
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

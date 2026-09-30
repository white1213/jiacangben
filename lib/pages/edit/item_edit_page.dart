import 'package:flutter/material.dart';

import '../../consts.dart';
import '../../database/item_service.dart';
import '../../database/location_service.dart';
import '../../database/tag_service.dart';
import '../../model/storage_location.dart';
import '../../model/stored_item.dart';
import '../../model/tag.dart';
import '../../model/tag_relation.dart';
import 'tag_field.dart';

/// 新增 / 编辑普通物件（修改收纳位置即完成挪动）
class ItemEditPage extends StatefulWidget {
  final StoredItem? item; // null = 新增
  final int? presetLocationId; // 从某位置详情页新增时预选

  const ItemEditPage({super.key, this.item, this.presetLocationId});

  @override
  State<ItemEditPage> createState() => _ItemEditPageState();
}

class _ItemEditPageState extends State<ItemEditPage> {
  final ItemService _itemService = ItemService();
  final LocationService _locationService = LocationService();
  final TagService _tagService = TagService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _countCtrl;
  late final TextEditingController _noteCtrl;

  int? _locationId;
  List<StorageLocation> _locations = const [];
  List<Tag> _allTags = const [];
  Set<int> _selectedTagIds = {};

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _countCtrl = TextEditingController(text: (item?.count ?? 1).toString());
    _noteCtrl = TextEditingController(text: item?.note ?? '');
    _locationId = item?.locationId ?? widget.presetLocationId;
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _countCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final locations = await _locationService.listAll();
    final tags = await _tagService.listAll();
    final existing = widget.item;
    final byOwner = existing?.id == null
        ? const <int, List<Tag>>{}
        : await _tagService.tagsByOwner(TagRelation.ownerTypeStoredItem);
    if (!mounted) return;
    setState(() {
      _locations = locations;
      _allTags = tags;
      _selectedTagIds = (byOwner[existing!.id] ?? const <Tag>[]).map((t) => t.id!).toSet();
      // 防御：关联位置已不存在时回退为未归位
      if (_locationId != null && !locations.any((l) => l.id == _locationId)) {
        _locationId = null;
      }
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Tag?> _createTag(String name) async {
    try {
      final tag = await _tagService.getOrCreate(name);
      if (!mounted) return tag;
      setState(() {
        if (!_allTags.any((t) => t.id == tag.id)) {
          _allTags = [..._allTags, tag];
        }
      });
      return tag;
    } catch (e) {
      if (mounted) _snack('新建标签失败：$e');
      return null;
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return _snack('请输入物件名称');
    final countText = _countCtrl.text.trim();
    final count = countText.isEmpty ? 1 : int.tryParse(countText);
    if (count == null || count < 0) return _snack('数量必须是大于等于 0 的整数');
    final note = _noteCtrl.text.trim();
    final item = StoredItem(
      id: widget.item?.id,
      name: name,
      count: count,
      locationId: _locationId,
      note: note.isEmpty ? null : note,
    );
    if (_isEditing) {
      await _itemService.update(item, tagIds: _selectedTagIds);
    } else {
      await _itemService.insert(item, tagIds: _selectedTagIds);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.item?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除物件'),
        content: Text('确定删除「${widget.item!.name}」吗？该操作不可撤销。'),
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
    await _itemService.delete(id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑物件' : '新增物件'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: kColorExpired),
              tooltip: '删除',
              onPressed: _delete,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.check),
        label: const Text('保存'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        children: [
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: '名称 *'),
          ),
          TextFormField(
            controller: _countCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '数量 *', hintText: '整数，默认 1'),
          ),
          DropdownButtonFormField<int?>(
            initialValue: _locationId,
            decoration: const InputDecoration(labelText: '收纳位置', hintText: '修改位置即挪动物件'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('未归位')),
              for (final location in _locations)
                DropdownMenuItem<int?>(value: location.id, child: Text(location.name)),
            ],
            onChanged: (v) => setState(() => _locationId = v),
          ),
          const SizedBox(height: 12),
          Text('标签', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          TagField(
            tags: _allTags,
            selectedTagIds: _selectedTagIds,
            onChanged: (ids) => setState(() => _selectedTagIds = ids),
            createTag: _createTag,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: '备注'),
            minLines: 2,
            maxLines: 4,
          ),
        ],
      ),
    );
  }
}

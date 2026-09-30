import 'package:flutter/material.dart';

import '../../consts.dart';
import '../../database/category_service.dart';
import '../../database/supply_service.dart';
import '../../database/tag_service.dart';
import '../../model/home_supply.dart';
import '../../model/item_category.dart';
import '../../model/tag.dart';
import '../../model/tag_relation.dart';
import '../../service/expiry_service.dart';
import '../../utils/date_utils.dart';
import 'tag_field.dart';

/// 新增 / 编辑消耗物资
class SupplyEditPage extends StatefulWidget {
  final HomeSupply? supply; // null = 新增

  const SupplyEditPage({super.key, this.supply});

  @override
  State<SupplyEditPage> createState() => _SupplyEditPageState();
}

class _SupplyEditPageState extends State<SupplyEditPage> {
  final SupplyService _service = SupplyService();
  final TagService _tagService = TagService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _afterOpenDaysCtrl;
  late final TextEditingController _noteCtrl;

  /// 页面内日期统一使用本地时区（选择器语义），入库时由 Model 统一转 UTC
  DateTime? _purchaseDate;
  DateTime? _expireDate;
  DateTime? _openDate;
  bool _isOpened = false;

  List<Tag> _allTags = const [];
  Set<int> _selectedTagIds = {};
  List<ItemCategory> _categories = const []; // v1.1：消耗物资分类
  int? _categoryId;

  bool get _isEditing => widget.supply != null;

  @override
  void initState() {
    super.initState();
    final s = widget.supply;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _afterOpenDaysCtrl = TextEditingController(text: s?.afterOpenDays?.toString() ?? '');
    _noteCtrl = TextEditingController(text: s?.note ?? '');
    _purchaseDate = s?.purchaseDate.toLocal();
    _expireDate = s?.expireDate.toLocal();
    _openDate = s?.openDate?.toLocal();
    _isOpened = s?.isOpened ?? false;
    _categoryId = s?.categoryId;
    _loadTags();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _afterOpenDaysCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    final tags = await _tagService.listAll();
    final categories = await CategoryService().listAll(targetType: ItemCategory.targetTypeSupply);
    final existing = widget.supply;
    final byOwner = existing?.id == null
        ? const <int, List<Tag>>{}
        : await _tagService.tagsByOwner(TagRelation.ownerTypeSupply);
    if (!mounted) return;
    setState(() {
      _allTags = tags;
      _categories = categories;
      _selectedTagIds = (byOwner[existing!.id] ?? const <Tag>[]).map((t) => t.id!).toSet();
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

  int? _parsedAfterOpenDays() {
    final text = _afterOpenDaysCtrl.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return _snack('请输入物资名称');
    if (_purchaseDate == null) return _snack('请选择购入日期');
    if (_expireDate == null) return _snack('请选择外包装到期日期');
    int? afterOpenDays;
    if (_isOpened) {
      if (_openDate == null) return _snack('已开封，请选择开封日期');
      afterOpenDays = _parsedAfterOpenDays();
      if (_afterOpenDaysCtrl.text.trim().isNotEmpty && (afterOpenDays == null || afterOpenDays < 0)) {
        return _snack('开封后使用天数必须是大于等于 0 的整数');
      }
    }
    final note = _noteCtrl.text.trim();
    final supply = HomeSupply(
      id: widget.supply?.id,
      name: name,
      purchaseDate: _purchaseDate!,
      expireDate: _expireDate!,
      isOpened: _isOpened,
      openDate: _isOpened ? _openDate : null,
      afterOpenDays: _isOpened ? afterOpenDays : null,
      categoryId: _categoryId,
      note: note.isEmpty ? null : note,
    );
    if (_isEditing) {
      await _service.update(supply, tagIds: _selectedTagIds);
    } else {
      await _service.insert(supply, tagIds: _selectedTagIds);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.supply?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除物资'),
        content: Text('确定删除「${widget.supply!.name}」吗？该操作不可撤销。'),
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
    await _service.delete(id);
    if (mounted) Navigator.of(context).pop();
  }

  /// 最终失效时间实时预览
  Widget? _buildPreview() {
    if (_expireDate == null) return null;
    final tmp = HomeSupply(
      name: '',
      purchaseDate: _purchaseDate ?? _expireDate!,
      expireDate: _expireDate!,
      isOpened: _isOpened,
      openDate: _openDate,
      afterOpenDays: _parsedAfterOpenDays(),
    );
    final status = ExpiryService.statusOf(tmp);
    final color = switch (status) {
      ExpiryStatus.expired => kColorExpired,
      ExpiryStatus.expiringSoon => const Color(0xFF8A6D00),
      ExpiryStatus.normal => Colors.grey,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '最终失效时间：${formatLocalDate(ExpiryService.finalExpireDate(tmp))}'
        ' · ${ExpiryService.labelOf(status)}（${ExpiryService.describeLeft(tmp)}）',
        style: TextStyle(color: color, fontSize: 13),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑物资' : '新增物资'),
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
            decoration: const InputDecoration(labelText: '名称 *', hintText: '如：牛奶、洗面奶'),
          ),
          // v1.1：分类下拉（消耗物资分类）
          DropdownButtonFormField<int?>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: '分类'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('无分类')),
              for (final c in _categories) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          _dateTile('购入日期 *', _purchaseDate, (d) => setState(() => _purchaseDate = d)),
          _dateTile('外包装到期日期 *', _expireDate, (d) => setState(() => _expireDate = d)),
          CheckboxListTile(
            value: _isOpened,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('已开封'),
            onChanged: (v) => setState(() {
              _isOpened = v ?? false;
              if (!_isOpened) {
                _openDate = null;
                _afterOpenDaysCtrl.clear();
              }
            }),
          ),
          if (_isOpened) ...[
            _dateTile('开封日期 *', _openDate, (d) => setState(() => _openDate = d)),
            TextFormField(
              controller: _afterOpenDaysCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '开封后建议使用天数',
                hintText: '留空则只按外包装到期时间计算',
              ),
            ),
          ],
          _buildPreview() ?? const SizedBox.shrink(),
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

  Widget _dateTile(String label, DateTime? value, ValueChanged<DateTime> onPicked) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      trailing: Text(
        value == null ? '未选择' : formatLocalDate(value),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: value == null ? Colors.grey : null,
        ),
      ),
      onTap: () async {
        final picked = await pickDate(context, value);
        if (picked != null) onPicked(picked);
      },
    );
  }
}

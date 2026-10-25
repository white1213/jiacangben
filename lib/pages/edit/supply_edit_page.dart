import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../consts.dart';
import '../../database/attachment_service.dart';
import '../../database/category_service.dart';
import '../../database/consume_log_service.dart';
import '../../database/supply_service.dart';
import '../../database/tag_service.dart';
import '../../database/template_service.dart';
import '../../model/entry_template.dart';
import '../../model/home_supply.dart';
import '../../model/item_category.dart';
import '../../model/media_attachment.dart';
import '../../model/tag.dart';
import '../../model/tag_relation.dart';
import '../../service/expiry_service.dart';
import '../../service/settings_service.dart';
import '../../utils/date_utils.dart';
import 'attachment_section.dart';
import 'consume_history_section.dart';
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
  late final TextEditingController _countCtrl; // v1.4：库存数量
  late final TextEditingController _prodCtrl; // v1.5：生产日期（8 位数字，如 20250901）
  late final TextEditingController _shelfCtrl; // v1.5：保质期时长数值

  /// v1.5：到期日双模式 —— true = 算式（生产日期+保质期时长，App 计算到期日），false = 直接选日期。
  /// 新增默认算式；编辑按原录入方式回填。
  bool _formulaMode = true;
  ShelfUnit _shelfUnit = ShelfUnit.month; // v1.5：时长单位，默认月（包装最常见）

  /// v1.4：领用出库后的剩余库存（编辑态实时刷新；新增态为 null）
  int? _remainingCount;

  /// 页面内日期统一使用本地时区（选择器语义），入库时由 Model 统一转 UTC
  DateTime? _purchaseDate;
  DateTime? _expireDate;
  DateTime? _openDate;
  bool _isOpened = false;

  List<Tag> _allTags = const [];
  Set<int> _selectedTagIds = {};
  List<ItemCategory> _categories = const []; // v1.1：消耗物资分类
  int? _categoryId;
  List<EntryTemplate> _templates = const []; // v1.2：录入模板（仅新增时可选）
  EntryTemplate? _selectedTemplate;
  int _warnDays = kExpiringSoonDays; // 设置页自定义的临期预警天数（预览用）

  bool get _isEditing => widget.supply != null;

  @override
  void initState() {
    super.initState();
    final s = widget.supply;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _afterOpenDaysCtrl = TextEditingController(text: s?.afterOpenDays?.toString() ?? '');
    _noteCtrl = TextEditingController(text: s?.note ?? '');
    _countCtrl = TextEditingController(text: (s?.count ?? 1).toString());
    _prodCtrl = TextEditingController(
      text: s?.productionDate == null ? '' : formatLocalDate(s!.productionDate!).replaceAll('-', ''),
    );
    _shelfCtrl = TextEditingController(text: s?.shelfValue?.toString() ?? '');
    _shelfUnit = s?.shelfUnit ?? ShelfUnit.month;
    _formulaMode = s?.hasShelfFormula ?? true; // 编辑按原方式回填，新增默认算式
    _remainingCount = s?.count;
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
    _countCtrl.dispose();
    _prodCtrl.dispose();
    _shelfCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    final tags = await _tagService.listAll();
    final categories = await CategoryService().listAll(targetType: ItemCategory.targetTypeSupply);
    final templates = await TemplateService().listAll(targetType: EntryTemplate.targetTypeSupply);
    final warnDays = await SettingsService().getWarnDays();
    final existing = widget.supply;
    final byOwner = existing?.id == null
        ? const <int, List<Tag>>{}
        : await _tagService.tagsByOwner(TagRelation.ownerTypeSupply);
    if (!mounted) return;
    setState(() {
      _allTags = tags;
      _categories = categories;
      _templates = templates;
      _warnDays = warnDays;
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

  /// v1.5：解析 8 位数字生产日期（yyyymmdd）为本地时区当日零点；非法返回 null
  DateTime? _parsedProductionDate() {
    final text = _prodCtrl.text.trim();
    if (text.length != 8) return null;
    final year = int.tryParse(text.substring(0, 4));
    final month = int.tryParse(text.substring(4, 6));
    final day = int.tryParse(text.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day); // 越界日（如 2-30）由 Dart 自动规整为 3 月初
  }

  /// v1.5：算式输入齐全时构造临时对象用于计算（输入不全返回 null）
  HomeSupply? _formulaSupply() {
    final prod = _parsedProductionDate();
    final value = int.tryParse(_shelfCtrl.text.trim());
    if (prod == null || value == null || value < 1) return null;
    return HomeSupply(
      name: '',
      purchaseDate: prod,
      expireDate: prod,
      productionDate: prod,
      shelfValue: value,
      shelfUnit: _shelfUnit,
    );
  }

  /// v1.5：当前生效的到期日（算式模式实时计算；日期模式为已选值）
  DateTime? _effectiveExpireDate() =>
      _formulaMode ? _formulaSupply()?.computeExpireDate() : _expireDate;

  /// v1.5：切换录入模式；离开算式模式时把算出的到期日带走，避免信息丢失
  void _switchFormulaMode(bool formula) {
    setState(() {
      if (!formula) {
        final computed = _formulaSupply()?.computeExpireDate();
        if (computed != null) _expireDate = computed;
      }
      _formulaMode = formula;
    });
  }

  /// v1.2：应用录入模板预填表单（用户可继续手动修改）
  /// v1.7：预填保质期时长+单位（生产日期不预填——包装上每件不同，照敲）
  void _applyTemplate(EntryTemplate? template) {
    setState(() {
      _selectedTemplate = template;
      if (template == null) return;
      final fields = template.presetFields;
      final name = fields['name'];
      if (name is String && name.isNotEmpty) _nameCtrl.text = name;
      final shelf = fields['shelfValue'];
      if (shelf is num) _shelfCtrl.text = shelf.toInt().toString();
      final unit = ShelfUnit.fromName(fields['shelfUnit'] as String?);
      if (unit != null) _shelfUnit = unit;
      final days = fields['afterOpenDays'];
      if (days is num) _afterOpenDaysCtrl.text = days.toInt().toString();
      final note = fields['note'];
      if (note is String && note.isNotEmpty) _noteCtrl.text = note;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return _snack('请输入物资名称');
    if (_purchaseDate == null) return _snack('请选择购入日期');
    // v1.5：按录入模式解析到期日与算式三件套
    final DateTime expireDate;
    final DateTime? productionDate;
    final int? shelfValue;
    final ShelfUnit? shelfUnit;
    if (_formulaMode) {
      final prod = _parsedProductionDate();
      if (prod == null) return _snack('请输入正确的生产日期（8 位数字，如 20250901）');
      final value = int.tryParse(_shelfCtrl.text.trim());
      if (value == null || value < 1) return _snack('保质期时长必须是大于等于 1 的整数');
      productionDate = prod;
      shelfValue = value;
      shelfUnit = _shelfUnit;
      expireDate = _formulaSupply()!.computeExpireDate();
    } else {
      if (_expireDate == null) return _snack('请选择外包装到期日期');
      productionDate = null;
      shelfValue = null;
      shelfUnit = null;
      expireDate = _expireDate!;
    }
    int? afterOpenDays;
    if (_isOpened) {
      if (_openDate == null) return _snack('已开封，请选择开封日期');
      // v1.3 校验：开封日期晚于外包装到期日期属于非法数据
      if (_openDate!.isAfter(expireDate)) {
        return _snack('开封日期不能晚于外包装到期日期，请检查填写');
      }
      afterOpenDays = _parsedAfterOpenDays();
      if (_afterOpenDaysCtrl.text.trim().isNotEmpty && (afterOpenDays == null || afterOpenDays < 0)) {
        return _snack('开封后使用天数必须是大于等于 0 的整数');
      }
    }
    final note = _noteCtrl.text.trim();
    // v1.4：库存数量校验（整数 >= 0；领用出库会同步改写该输入框）
    final count = int.tryParse(_countCtrl.text.trim()) ?? 1;
    if (count < 0) return _snack('数量必须是大于等于 0 的整数');
    final supply = HomeSupply(
      id: widget.supply?.id,
      name: name,
      purchaseDate: _purchaseDate!,
      expireDate: expireDate,
      isOpened: _isOpened,
      openDate: _isOpened ? _openDate : null,
      afterOpenDays: _isOpened ? afterOpenDays : null,
      categoryId: _categoryId,
      count: count,
      productionDate: productionDate,
      shelfValue: shelfValue,
      shelfUnit: shelfUnit,
      note: note.isEmpty ? null : note,
    );
    try {
      if (_isEditing) {
        await _service.update(supply, tagIds: _selectedTagIds);
      } else {
        await _service.insert(supply, tagIds: _selectedTagIds);
      }
    } catch (e) {
      // 写库失败时给出可见提示，避免“点了没反应”
      if (mounted) _snack('保存失败：$e');
      return;
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
    // v1.2：有关联图片时询问文件处理方式
    final cleanup = await confirmAttachmentCleanup(
      context,
      AttachmentService(),
      MediaAttachment.ownerTypeSupply,
      [id],
    );
    if (cleanup == AttachmentCleanup.cancel) return;
    if (cleanup != null) {
      await AttachmentService().purgeForOwners(
        MediaAttachment.ownerTypeSupply,
        [id],
        deleteFiles: cleanup == AttachmentCleanup.deleteFiles,
      );
    }
    await _service.delete(id);
    if (mounted) Navigator.of(context).pop();
  }

  /// v1.4：领用出库（弹窗输入扣减数量 + 可选备注；库存扣减与流水写入在同一事务）
  Future<void> _consume() async {
    final id = widget.supply?.id;
    if (id == null) return;
    final countCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('领用出库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('当前剩余：${_remainingCount ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: countCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '本次领用数量 *', hintText: '正整数，不超过剩余库存'),
            ),
            TextField(
              controller: remarkCtrl,
              decoration: const InputDecoration(labelText: '备注', hintText: '如：吃掉 / 过期丢弃 / 使用完毕'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认出库')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final deduct = int.tryParse(countCtrl.text.trim());
    if (deduct == null || deduct <= 0) {
      _snack('领用数量必须是大于 0 的整数');
      return;
    }
    try {
      final remaining = await ConsumeLogService().consume(
        supplyId: id,
        deductCount: deduct,
        remark: remarkCtrl.text.trim().isEmpty ? null : remarkCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _remainingCount = remaining;
        _countCtrl.text = remaining.toString();
      });
      _snack('已出库 $deduct，剩余 $remaining（流水已记录）');
    } on StateError catch (e) {
      _snack(e.message.replaceAll('Exception: ', ''));
    } catch (e) {
      _snack('出库失败：$e');
    }
  }

  /// 最终失效时间实时预览（v1.5：算式模式下随输入实时计算）
  Widget? _buildPreview() {
    final expire = _effectiveExpireDate();
    if (expire == null) return null;
    final tmp = HomeSupply(
      name: '',
      purchaseDate: _purchaseDate ?? expire,
      expireDate: expire,
      isOpened: _isOpened,
      openDate: _openDate,
      afterOpenDays: _parsedAfterOpenDays(),
    );
    final status = ExpiryService.statusOf(tmp, warnDays: _warnDays);
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
          // v1.2：新增时可选录入模板自动预填
          if (!_isEditing && _templates.isNotEmpty)
            DropdownButtonFormField<EntryTemplate?>(
              initialValue: _selectedTemplate,
              decoration: const InputDecoration(
                labelText: '使用录入模板',
                hintText: '选择后自动预填，可再修改',
              ),
              items: [
                const DropdownMenuItem<EntryTemplate?>(value: null, child: Text('不使用模板')),
                for (final t in _templates) DropdownMenuItem<EntryTemplate?>(value: t, child: Text(t.name)),
              ],
              onChanged: _applyTemplate,
            ),
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
          // v1.4：库存数量
          TextFormField(
            controller: _countCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '数量 *', hintText: '整数，默认 1；领用出库自动扣减'),
          ),
          _dateTile('购入日期 *', _purchaseDate, (d) => setState(() => _purchaseDate = d)),
          // v1.5：到期日双模式录入 —— 算式（生产日期+保质期）或直接选日期
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('生产日期+保质期')),
                ButtonSegment(value: false, label: Text('直接选日期')),
              ],
              selected: {_formulaMode},
              onSelectionChanged: (s) => _switchFormulaMode(s.first),
            ),
          ),
          if (_formulaMode) ...[
            TextFormField(
              controller: _prodCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(
                labelText: '生产日期 *',
                hintText: '照包装敲 8 位数字，如 20250901',
                suffixIcon: IconButton(
                  tooltip: '日历选择',
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: () async {
                    final picked = await pickDate(context, _parsedProductionDate());
                    if (picked != null) {
                      setState(() => _prodCtrl.text = formatLocalDate(picked).replaceAll('-', ''));
                    }
                  },
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _shelfCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '保质期 *',
                      hintText: '时长数字，如 9',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<ShelfUnit>(
                  segments: const [
                    ButtonSegment(value: ShelfUnit.day, label: Text('天')),
                    ButtonSegment(value: ShelfUnit.month, label: Text('月')),
                    ButtonSegment(value: ShelfUnit.year, label: Text('年')),
                  ],
                  selected: {_shelfUnit},
                  onSelectionChanged: (s) => setState(() => _shelfUnit = s.first),
                ),
              ],
            ),
          ] else
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
          // v1.4：领用出库入口（仅编辑已有物资时可用）
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _consume,
                      icon: const Icon(Icons.outbound),
                      label: const Text('领用出库'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('当前剩余：${_remainingCount ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
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
          const SizedBox(height: 16),
          // v1.2：图片附件（新增记录需先保存拿到 id）
          if (_isEditing)
            AttachmentSection(
              ownerType: MediaAttachment.ownerTypeSupply,
              ownerId: widget.supply!.id!,
            )
          else
            Text(
              '提示：保存后可返回编辑页添加图片附件',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          const SizedBox(height: 16),
          // v1.4：出库流水历史（只读，不可编辑/删除）
          if (_isEditing)
            ConsumeHistorySection(supplyId: widget.supply!.id!)
          else
            Text(
              '提示：保存后可进行领用出库并生成流水',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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

import 'package:flutter/material.dart';

import '../consts.dart';
import '../database/attachment_service.dart';
import '../database/category_service.dart';
import '../database/saved_filter_service.dart';
import '../database/supply_service.dart';
import '../database/tag_service.dart';
import '../model/home_supply.dart';
import '../model/item_category.dart';
import '../model/list_filter.dart';
import '../model/media_attachment.dart';
import '../model/saved_filter.dart';
import '../model/tag.dart';
import '../model/tag_relation.dart';
import '../service/expiry_service.dart';
import '../service/settings_service.dart';
import '../utils/date_utils.dart';
import '../utils/list_sort.dart';
import 'edit/attachment_section.dart';
import 'edit/supply_edit_page.dart';
import 'filter_dialog.dart';

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

/// 状态筛选。urgent = 临期+过期合并视图，仅作小部件深链的初始筛选，
/// 筛选弹窗不提供该选项（用户改选后自动回到常规三态）。
enum SupplyStatusFilter { all, expiringSoon, expired, urgent }

/// 消耗物资列表页
/// v1.1 新增：多选批量操作（批量标记已开封 / 批量删除）
class HomeSupplyListPage extends StatefulWidget {
  /// v1.6：初始状态筛选（小部件点击深链传 urgent；默认 all）
  final SupplyStatusFilter initialFilter;

  const HomeSupplyListPage({super.key, this.initialFilter = SupplyStatusFilter.all});

  @override
  State<HomeSupplyListPage> createState() => _HomeSupplyListPageState();
}

class _HomeSupplyListPageState extends State<HomeSupplyListPage> {
  final SupplyService _service = SupplyService();
  final TagService _tagService = TagService();

  bool _loading = true;
  List<HomeSupply> _supplies = const [];
  Map<int, List<Tag>> _tagsByOwner = const {};
  // v1.3：状态筛选保留（原顶部段选择器移入筛选弹窗），分类+标签走 ListFilter
  SupplyStatusFilter _filter = SupplyStatusFilter.all;
  ListFilter _listFilter = ListFilter();
  List<ItemCategory> _categories = const [];

  // v1.1 多选模式
  bool _selectMode = false;
  Set<int> _selectedIds = {};

  // v1.2 保存筛选条件
  final SavedFilterService _savedFilterService = SavedFilterService();

  // 设置页自定义的临期预警天数
  int _warnDays = kExpiringSoonDays;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _init();
  }

  /// v1.3：进入页面还原上次激活的筛选条件（分类+标签），再加载列表
  Future<void> _init() async {
    final active = await SettingsService().getActiveFilter(ItemCategory.targetTypeSupply);
    if (active != null && mounted) {
      setState(() => _listFilter = active);
    }
    await _reload();
  }

  Future<void> _reload() async {
    // v1.3：分类+标签筛选下沉到 SQL（tag_relation 子查询 OR 语义），状态筛选在内存中计算
    final supplies = await _service.listFiltered(
      categoryId: _listFilter.categoryId,
      tagIds: _listFilter.tagIds,
    );
    final tags = await _tagService.tagsByOwner(TagRelation.ownerTypeSupply);
    final categories = await CategoryService().listAll(targetType: ItemCategory.targetTypeSupply);
    final warnDays = await SettingsService().getWarnDays();
    // v1.4：按当前排序配置排序（录入顺序/名称/数量/到期时间）
    sortSupplies(supplies, _listFilter.sortBy);
    if (!mounted) return;
    setState(() {
      _supplies = supplies;
      _tagsByOwner = tags;
      _categories = categories;
      _warnDays = warnDays;
      _loading = false;
    });
  }

  List<HomeSupply> get _filtered {
    switch (_filter) {
      case SupplyStatusFilter.all:
        return _supplies;
      case SupplyStatusFilter.expiringSoon:
        return _supplies.where((s) => ExpiryService.statusOf(s, warnDays: _warnDays) == ExpiryStatus.expiringSoon).toList();
      case SupplyStatusFilter.expired:
        return _supplies.where((s) => ExpiryService.statusOf(s) == ExpiryStatus.expired).toList();
      case SupplyStatusFilter.urgent:
        // v1.6：临期+过期合并（小部件深链落点）
        return _supplies
            .where((s) => ExpiryService.statusOf(s, warnDays: _warnDays) != ExpiryStatus.normal)
            .toList();
    }
  }

  /// v1.3：是否存在激活的筛选条件（弹窗 Badge 高亮）
  bool get _hasActiveFilter => _listFilter.isNotEmpty || _filter != SupplyStatusFilter.all;

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
    final ids = _selectedIds.toList();
    // v1.2：有关联图片时询问文件处理方式
    final cleanup = await confirmAttachmentCleanup(
      context,
      AttachmentService(),
      MediaAttachment.ownerTypeSupply,
      ids,
    );
    if (cleanup == AttachmentCleanup.cancel) return;
    if (cleanup != null) {
      await AttachmentService().purgeForOwners(
        MediaAttachment.ownerTypeSupply,
        ids,
        deleteFiles: cleanup == AttachmentCleanup.deleteFiles,
      );
    }
    final deleted = await _service.batchDelete(ids);
    _exitSelectMode();
    await _reload();
    if (mounted) _snack('已删除 $deleted 条物资');
  }

  /// 条目长按上下文菜单（编辑 / 多选 / 删除）
  Future<void> _showItemMenu(HomeSupply supply) async {
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
              leading: const Icon(Icons.delete_outline, color: kColorExpired),
              title: const Text('删除', style: TextStyle(color: kColorExpired)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _openEditor(supply);
      case 'select':
        _enterSelectMode(supply.id);
      case 'delete':
        await _deleteSingle(supply);
    }
  }

  /// 单条删除（含关联图片处理确认）
  Future<void> _deleteSingle(HomeSupply supply) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除物资'),
        content: Text('确定删除「${supply.name}」吗？该操作不可撤销。'),
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
    if (ok != true || !mounted) return;
    final cleanup = await confirmAttachmentCleanup(
      context,
      AttachmentService(),
      MediaAttachment.ownerTypeSupply,
      [supply.id!],
    );
    if (cleanup == AttachmentCleanup.cancel) return;
    if (cleanup != null) {
      await AttachmentService().purgeForOwners(
        MediaAttachment.ownerTypeSupply,
        [supply.id!],
        deleteFiles: cleanup == AttachmentCleanup.deleteFiles,
      );
    }
    await _service.delete(supply.id!);
    await _reload();
    if (mounted) _snack('已删除「${supply.name}」');
  }

  /// v1.3：打开筛选弹窗（状态 + 分类 + 标签），应用后持久化激活筛选并刷新
  Future<void> _showFilter() async {
    final tags = await _tagService.listAll();
    if (!mounted) return;
    final result = await showFilterDialog(
      context,
      categories: _categories,
      tags: tags,
      initialFilter: _listFilter,
      initialStatus: _filter.name,
      categoryTargetType: ItemCategory.targetTypeSupply,
    );
    if (result == null || !mounted) return;
    setState(() {
      _filter = SupplyStatusFilter.values.firstWhere(
        (v) => v.name == result.status,
        orElse: () => SupplyStatusFilter.all,
      );
      _listFilter = result.filter;
    });
    // 激活筛选持久化（供子集导出与下次进入还原；含排序配置）
    await SettingsService().setActiveFilter(ItemCategory.targetTypeSupply, _listFilter);
    await _reload();
  }

  /// v1.4：切换排序方式（与筛选、搜索叠加；持久化到激活筛选）
  Future<void> _changeSort(String sortBy) async {
    if (sortBy == _listFilter.sortBy) return;
    setState(() {
      _listFilter.sortBy = sortBy;
      // 排序仅影响展示顺序，直接对已加载数据重排即可，无需重新查库
      sortSupplies(_supplies, sortBy);
    });
    await SettingsService().setActiveFilter(ItemCategory.targetTypeSupply, _listFilter);
  }

  /// v1.2：保存当前筛选条件（v1.3 起完整序列化 状态+分类+标签，向下兼容旧数据）
  Future<void> _manageSavedFilters() async {
    final filters = await _savedFilterService.listAll(SavedFilter.targetTypeSupply);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> saveCurrent() async {
            final controller = TextEditingController();
            final name = await showDialog<String>(
              context: ctx,
              builder: (ctx) => AlertDialog(
                title: const Text('保存当前筛选'),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '方案名称，如：临期关注'),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('保存')),
                ],
              ),
            );
            if (name == null || name.trim().isEmpty) return;
            final saved = SavedFilter(
              name: name.trim(),
              targetType: SavedFilter.targetTypeSupply,
              // v1.3：状态 + 分类 + 标签一并序列化
              filterJson: {
                'status': _filter.name,
                ..._listFilter.toJson(),
              },
            );
            await _savedFilterService.insert(saved);
            setDialogState(() => filters.add(saved));
          }

          return AlertDialog(
            title: const Text('筛选方案'),
            content: SizedBox(
              width: 280,
              child: filters.isEmpty
                  ? const Text('暂无保存的筛选方案', style: TextStyle(color: Colors.grey))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final f in filters)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.filter_list, size: 20),
                            title: Text(f.name),
                            subtitle: Text('筛选：${_statusLabel(f.filterJson['status']?.toString())}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // v1.3：筛选方案重命名
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () async {
                                    final newName = await _promptText('重命名方案', f.name);
                                    if (newName == null || newName.trim().isEmpty || newName.trim() == f.name) return;
                                    await _savedFilterService.update(
                                      SavedFilter(
                                        id: f.id,
                                        name: newName.trim(),
                                        targetType: f.targetType,
                                        filterJson: f.filterJson,
                                      ),
                                    );
                                    setDialogState(() {
                                      f.name = newName.trim();
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () async {
                                    await _savedFilterService.delete(f.id!);
                                    setDialogState(() => filters.remove(f));
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              final status = f.filterJson['status']?.toString();
                              setState(() {
                                _filter = SupplyStatusFilter.values.firstWhere(
                                  (v) => v.name == status,
                                  orElse: () => SupplyStatusFilter.all,
                                );
                                // v1.3：还原分类 + 标签筛选（旧版数据缺键视为未筛选）
                                _listFilter = ListFilter.fromJson(f.filterJson);
                              });
                              SettingsService().setActiveFilter(ItemCategory.targetTypeSupply, _listFilter);
                              Navigator.pop(ctx);
                            },
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(onPressed: saveCurrent, child: const Text('保存当前筛选')),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ],
          );
        },
      ),
    );
  }

  String _statusLabel(String? status) {
    return switch (status) {
      'expiringSoon' => '临期',
      'expired' => '已过期',
      _ => '全部',
    };
  }

  /// 通用单行文本输入弹窗（重命名等）
  Future<String?> _promptText(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('确定')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: _selectMode
          ? _buildSelectionAppBar()
          : AppBar(
              title: const Text('消耗物资库'),
              actions: [
                // v1.4：排序下拉（与筛选/搜索叠加）
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  tooltip: '排序',
                  onSelected: _changeSort,
                  itemBuilder: (_) => [
                    // 消耗物资列表显示全部排序项（含到期时间升序）
                    for (final (key, label, _) in kListSortOptions)
                      CheckedPopupMenuItem<String>(
                        value: key,
                        checked: _listFilter.sortBy == key,
                        child: Text(label),
                      ),
                  ],
                ),
                // v1.3：筛选弹窗入口，激活时 Badge 高亮
                Badge(
                  isLabelVisible: _hasActiveFilter,
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
                // v1.2：保存筛选方案
                IconButton(
                  icon: const Icon(Icons.bookmark_border),
                  tooltip: '筛选方案',
                  onPressed: _manageSavedFilters,
                ),
              ],
            ),
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
          // v1.3：原顶部状态段选择器已移入筛选弹窗（与分类、标签筛选整合）
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
            '购入：${formatLocalDate(supply.purchaseDate)} · 数量：${supply.count}'
            '${supply.isOpened ? ' · 已开封' : ''}'
            '${supply.hasShelfFormula ? ' · ${formatLocalDate(supply.productionDate!)}产 保${supply.shelfValue}${supply.shelfUnit!.label}' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        isThreeLine: true,
        onLongPress: () => _showItemMenu(supply),
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

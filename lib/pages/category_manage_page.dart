import 'package:flutter/material.dart';

import '../consts.dart';
import '../database/category_service.dart';
import '../model/item_category.dart';

/// v1.1：分类管理页面（区分消耗物资分类 / 普通物件分类）
class CategoryManagePage extends StatefulWidget {
  const CategoryManagePage({super.key});

  @override
  State<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends State<CategoryManagePage> {
  final CategoryService _service = CategoryService();

  bool _loading = true;
  String _tab = ItemCategory.targetTypeSupply;
  List<ItemCategory> _categories = const [];
  Map<int, int> _usageCounts = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final categories = await _service.listAll(targetType: _tab);
    final counts = await _service.usageCounts();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _usageCounts = counts;
      _loading = false;
    });
  }

  Future<void> _openEditor([ItemCategory? category]) async {
    final nameCtrl = TextEditingController(text: category?.name ?? '');
    final noteCtrl = TextEditingController(text: category?.note ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(category == null ? '新增分类' : '编辑分类'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '分类名称 *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: '备注'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text), child: const Text('保存')),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final note = noteCtrl.text.trim();
    if (category == null) {
      await _service.insert(ItemCategory(name: trimmed, targetType: _tab, note: note.isEmpty ? null : note));
    } else {
      category
        ..name = trimmed
        ..note = note.isEmpty ? null : note;
      await _service.update(category);
    }
    await _reload();
  }

  /// 删除分类前校验引用：存在物资/物件引用则禁止直接删除
  Future<void> _confirmDelete(ItemCategory category) async {
    final usage = _usageCounts[category.id] ?? 0;
    if (usage > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('无法删除「${category.name}」'),
          content: Text('当前有 $usage 条物资/物件正在使用该分类。请先在编辑表单中把这些记录改到其他分类（或无分类）后再删除。'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除分类'),
        content: Text('确定删除「${category.name}」吗？该操作不可撤销。'),
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
    if (ok == true) {
      await _service.delete(category.id!);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分类管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增分类'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: ItemCategory.targetTypeSupply, label: Text('消耗物资分类')),
                ButtonSegment(value: ItemCategory.targetTypeThing, label: Text('普通物件分类')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) {
                setState(() => _tab = s.first);
                _reload();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _categories.isEmpty
                    ? const Center(child: Text('暂无分类', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                        itemCount: _categories.length,
                        itemBuilder: (_, index) {
                          final c = _categories[index];
                          final usage = _usageCounts[c.id] ?? 0;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(c.name),
                              subtitle: Text(
                                '被引用 $usage 次${(c.note ?? '').trim().isEmpty ? '' : ' · ${c.note}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: '编辑',
                                    onPressed: () => _openEditor(c),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: kColorExpired),
                                    tooltip: '删除',
                                    onPressed: () => _confirmDelete(c),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

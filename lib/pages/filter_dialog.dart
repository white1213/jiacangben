import 'package:flutter/material.dart';

import '../model/item_category.dart';
import '../model/list_filter.dart';
import '../model/tag.dart';

/// v1.3：通用列表筛选弹窗（无路由页面，纯 Dialog）。
/// - 分类下拉（全部 = 不筛选分类）
/// - 标签 FilterChip 多选，OR 语义（任一命中即匹配）
/// - [showStatus] = true 时（消耗物资页）附带 全部/临期/已过期 状态段选择器
/// - 重置：清空全部条件；确定：返回 (状态值, ListFilter)
class FilterDialogResult {
  final String? status; // all / expiringSoon / expired（仅物资页有意义）
  final ListFilter filter;

  FilterDialogResult({required this.status, required this.filter});
}

class FilterDialog extends StatefulWidget {
  final List<ItemCategory> categories;
  final List<Tag> tags;
  final ListFilter initialFilter;
  final String? initialStatus; // 非 null 时显示状态段
  final String categoryTargetType; // ItemCategory.targetType*

  const FilterDialog({
    super.key,
    required this.categories,
    required this.tags,
    required this.initialFilter,
    this.initialStatus,
    required this.categoryTargetType,
  });

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  late int? _categoryId;
  late Set<int> _tagIds;
  late String? _status;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialFilter.categoryId;
    _tagIds = {...widget.initialFilter.tagIds};
    _status = widget.initialStatus ?? 'all';
  }

  bool get _hasTags => widget.tags.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories.where((c) => c.targetType == widget.categoryTargetType).toList();
    return AlertDialog(
      title: const Text('筛选'),
      content: SizedBox(
        width: 340,
        child: ListView(
          shrinkWrap: true,
          children: [
            // 状态筛选（仅消耗物资列表）
            if (widget.initialStatus != null) ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('全部')),
                  ButtonSegment(value: 'expiringSoon', label: Text('临期')),
                  ButtonSegment(value: 'expired', label: Text('已过期')),
                ],
                selected: {_status!},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
              const SizedBox(height: 12),
            ],
            // 分类下拉
            DropdownButtonFormField<int?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: '分类'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('全部（不筛选分类）')),
                for (final c in categories.where((c) => c.id != null))
                  DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            // 标签多选（OR 语义）
            Text('标签（任一命中即匹配）', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            if (!_hasTags)
              Text('暂无标签，可在录入时创建', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
            else
              Wrap(
                spacing: 8,
                runSpacing: 0,
                children: [
                  for (final tag in widget.tags)
                    if (tag.id != null)
                      FilterChip(
                        label: Text(tag.name),
                        selected: _tagIds.contains(tag.id),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _tagIds.add(tag.id!);
                          } else {
                            _tagIds.remove(tag.id);
                          }
                        }),
                      ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        // 重置：清空全部筛选条件
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            FilterDialogResult(status: 'all', filter: ListFilter()),
          ),
          child: const Text('重置'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            FilterDialogResult(status: _status, filter: ListFilter(categoryId: _categoryId, tagIds: _tagIds)),
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 供列表页调用的便捷入口：展示筛选弹窗并返回结果
Future<FilterDialogResult?> showFilterDialog(
  BuildContext context, {
  required List<ItemCategory> categories,
  required List<Tag> tags,
  required ListFilter initialFilter,
  String? initialStatus,
  required String categoryTargetType,
}) {
  return showDialog<FilterDialogResult>(
    context: context,
    builder: (_) => FilterDialog(
      categories: categories,
      tags: tags,
      initialFilter: initialFilter,
      initialStatus: initialStatus,
      categoryTargetType: categoryTargetType,
    ),
  );
}

/// 状态文案（弹窗内与导出说明共用）
String filterStatusLabel(String? status) {
  return switch (status) {
    'expiringSoon' => '临期',
    'expired' => '已过期',
    _ => '全部',
  };
}

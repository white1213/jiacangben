import 'package:flutter/material.dart';

import '../../model/tag.dart';

/// 标签选择区：展示全部标签（可勾选）+「新建标签」入口。
/// MVP：无独立标签管理页，不支持按标签筛选。
class TagField extends StatelessWidget {
  final List<Tag> tags;
  final Set<int> selectedTagIds;
  final ValueChanged<Set<int>> onChanged;

  /// 由宿主页面实现：查库去重并落库，返回新建（或已存在）的标签
  final Future<Tag?> Function(String name) createTag;

  const TagField({
    super.key,
    required this.tags,
    required this.selectedTagIds,
    required this.onChanged,
    required this.createTag,
  });

  Future<void> _addNewTag(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '标签名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final tag = await createTag(name.trim());
    if (tag == null || tag.id == null) return;
    if (!selectedTagIds.contains(tag.id)) {
      onChanged({...selectedTagIds, tag.id!});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in tags)
          if (tag.id != null)
            FilterChip(
              label: Text(tag.name),
              selected: selectedTagIds.contains(tag.id),
              onSelected: (value) {
                final next = {...selectedTagIds};
                if (value) {
                  next.add(tag.id!);
                } else {
                  next.remove(tag.id!);
                }
                onChanged(next);
              },
            ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('新建标签'),
          onPressed: () => _addNewTag(context),
        ),
      ],
    );
  }
}

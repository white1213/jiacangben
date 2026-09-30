import 'package:flutter/material.dart';

import '../consts.dart';
import '../database/tag_service.dart';
import '../model/tag.dart';

/// v1.1：独立标签管理页面
/// - 重命名：事务内更新（tag_relation 通过 tagId 引用，改名不影响关联）
/// - 删除：仅当无任何物资/物件关联时允许
class TagManagePage extends StatefulWidget {
  const TagManagePage({super.key});

  @override
  State<TagManagePage> createState() => _TagManagePageState();
}

class _TagManagePageState extends State<TagManagePage> {
  final TagService _service = TagService();

  bool _loading = true;
  List<Tag> _tags = const [];
  Map<int, int> _relationCounts = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final tags = await _service.listAll();
    final counts = await _service.relationCounts();
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _relationCounts = counts;
      _loading = false;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename(Tag tag) async {
    final controller = TextEditingController(text: tag.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('保存')),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == tag.name) return;
    try {
      await _service.rename(tag.id!, trimmed);
      await _reload();
    } on StateError catch (e) {
      _snack(e.message.replaceAll('Exception: ', ''));
    }
  }

  /// 删除无用标签：仅当没有任何关联时允许
  Future<void> _confirmDelete(Tag tag) async {
    final count = _relationCounts[tag.id] ?? 0;
    if (count > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('无法删除「${tag.name}」'),
          content: Text('当前有 $count 条物资/物件关联此标签。请先在编辑表单中取消关联后再删除。'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除标签'),
        content: Text('确定删除「${tag.name}」吗？该操作不可撤销。'),
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
      final deleted = await _service.deleteIfUnused(tag.id!);
      if (!deleted && mounted) _snack('删除失败：标签已被关联');
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('标签管理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tags.isEmpty
              ? const Center(child: Text('暂无标签，可在录入物资/物件时创建', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: _tags.length,
                  itemBuilder: (_, index) {
                    final tag = _tags[index];
                    final count = _relationCounts[tag.id] ?? 0;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.label_outline),
                        title: Text(tag.name),
                        subtitle: Text(count > 0 ? '关联 $count 条记录' : '未关联任何记录'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: '重命名',
                              onPressed: () => _rename(tag),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: count > 0 ? Colors.grey : kColorExpired,
                              ),
                              tooltip: count > 0 ? '有关联，不可删除' : '删除',
                              onPressed: () => _confirmDelete(tag),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

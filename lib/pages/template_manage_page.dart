import 'package:flutter/material.dart';

import '../database/template_service.dart';
import '../model/entry_template.dart';

/// v1.2：录入模板管理页。
/// 预设字段：物资模板 = 名称 + 开封后建议使用天数 + 备注；物件模板 = 名称 + 数量 + 备注。
/// 示例：护肤品模板预设开封后 90 天。
class TemplateManagePage extends StatefulWidget {
  const TemplateManagePage({super.key});

  @override
  State<TemplateManagePage> createState() => _TemplateManagePageState();
}

class _TemplateManagePageState extends State<TemplateManagePage> {
  final TemplateService _service = TemplateService();

  bool _loading = true;
  String _tab = EntryTemplate.targetTypeSupply;
  List<EntryTemplate> _templates = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final templates = await _service.listAll(targetType: _tab);
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _loading = false;
    });
  }

  String _describe(EntryTemplate t) {
    final parts = <String>[];
    final name = t.presetFields['name'];
    if (name is String && name.isNotEmpty) parts.add('名称：$name');
    final days = t.presetFields['afterOpenDays'];
    if (days is num) parts.add('开封后 $days 天');
    final count = t.presetFields['count'];
    if (count is num) parts.add('数量 ${count.toInt()}');
    final note = t.presetFields['note'];
    if (note is String && note.isNotEmpty) parts.add('备注：$note');
    return parts.isEmpty ? '（无预设内容）' : parts.join(' · ');
  }

  Future<void> _openEditor([EntryTemplate? template]) async {
    final nameCtrl = TextEditingController(text: template?.name ?? '');
    final presetNameCtrl = TextEditingController(text: template?.presetFields['name']?.toString() ?? '');
    final daysCtrl = TextEditingController(text: template?.presetFields['afterOpenDays']?.toString() ?? '');
    final countCtrl = TextEditingController(text: template?.presetFields['count']?.toString() ?? '');
    final noteCtrl = TextEditingController(text: template?.presetFields['note']?.toString() ?? '');
    final isSupply = _tab == EntryTemplate.targetTypeSupply;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(template == null ? '新增模板' : '编辑模板'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: '模板名称 *')),
              const SizedBox(height: 8),
              TextField(controller: presetNameCtrl, decoration: const InputDecoration(labelText: '预设名称')),
              if (isSupply)
                TextField(
                  controller: daysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '预设开封后建议天数', hintText: '如护肤品填 90'),
                ),
              if (!isSupply)
                TextField(
                  controller: countCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '预设数量'),
                ),
              TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: '预设备注')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final preset = <String, dynamic>{};
    if (presetNameCtrl.text.trim().isNotEmpty) preset['name'] = presetNameCtrl.text.trim();
    final days = int.tryParse(daysCtrl.text.trim());
    if (isSupply && days != null) preset['afterOpenDays'] = days;
    final count = int.tryParse(countCtrl.text.trim());
    if (!isSupply && count != null) preset['count'] = count;
    if (noteCtrl.text.trim().isNotEmpty) preset['note'] = noteCtrl.text.trim();

    if (template == null) {
      await _service.insert(EntryTemplate(name: name, targetType: _tab, presetFields: preset));
    } else {
      template
        ..name = name
        ..presetFields = preset;
      await _service.update(template);
    }
    await _reload();
  }

  Future<void> _confirmDelete(EntryTemplate template) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除模板'),
        content: Text('确定删除「${template.name}」吗？不影响已录入的数据。'),
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
    if (ok == true) {
      await _service.delete(template.id!);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('录入模板')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增模板'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: EntryTemplate.targetTypeSupply, label: Text('物资模板')),
                ButtonSegment(value: EntryTemplate.targetTypeThing, label: Text('物件模板')),
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
                : _templates.isEmpty
                    ? const Center(child: Text('暂无模板', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                        itemCount: _templates.length,
                        itemBuilder: (_, index) {
                          final t = _templates[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(t.name),
                              subtitle: Text(_describe(t), maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: '编辑',
                                    onPressed: () => _openEditor(t),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Color(0xFFE55555)),
                                    tooltip: '删除',
                                    onPressed: () => _confirmDelete(t),
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

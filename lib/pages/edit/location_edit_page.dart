import 'package:flutter/material.dart';

import '../../database/location_service.dart';
import '../../model/storage_location.dart';

/// 新增 / 编辑收纳位置（删除操作统一在列表页处理）
class LocationEditPage extends StatefulWidget {
  final StorageLocation? location; // null = 新增

  const LocationEditPage({super.key, this.location});

  @override
  State<LocationEditPage> createState() => _LocationEditPageState();
}

class _LocationEditPageState extends State<LocationEditPage> {
  final LocationService _service = LocationService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  bool get _isEditing => widget.location != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.location?.name ?? '');
    _descCtrl = TextEditingController(text: widget.location?.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入位置名称')),
      );
      return;
    }
    final description = _descCtrl.text.trim();
    final location = StorageLocation(
      id: widget.location?.id,
      name: name,
      description: description.isEmpty ? null : description,
    );
    if (_isEditing) {
      await _service.update(location);
    } else {
      await _service.insert(location);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑收纳位置' : '新增收纳位置')),
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
            decoration: const InputDecoration(labelText: '名称 *', hintText: '如：客厅柜子、书房抽屉'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descCtrl,
            decoration: const InputDecoration(labelText: '描述'),
            minLines: 2,
            maxLines: 4,
          ),
        ],
      ),
    );
  }
}

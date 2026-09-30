import 'package:flutter/material.dart';

import '../consts.dart';
import '../service/settings_service.dart';

/// 简易设置页：临期预警天数 + 关于
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settings = SettingsService();

  int _warnDays = kExpiringSoonDays;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final days = await _settings.getWarnDays();
    if (!mounted) return;
    setState(() => _warnDays = days);
  }

  /// 修改临期预警天数
  Future<void> _editWarnDays() async {
    final controller = TextEditingController(text: _warnDays.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('临期预警天数'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '天数（1-365）',
            helperText: '距最终失效时间小于等于该天数时标记为临期',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim())), child: const Text('保存')),
        ],
      ),
    );
    if (value == null) return;
    if (value < 1 || value > 365) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入 1-365 之间的整数')));
      }
      return;
    }
    await _settings.setWarnDays(value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            leading: const Icon(Icons.warning_amber_rounded),
            title: const Text('临期预警天数'),
            subtitle: Text('当前：$_warnDays 天（距失效时间 ≤ $_warnDays 天标记为临期）'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editWarnDays,
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            subtitle: Text('家藏本 · 单机本地台账\n数据全部保存在本机，无网络请求'),
          ),
          Center(
            child: Text(
              '版本 $kAppVersion',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

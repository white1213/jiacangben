import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../service/backup_service.dart';
import '../utils/date_utils.dart';

/// 备份与恢复页面
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final BackupService _service = BackupService();
  final TextEditingController _pasteController = TextEditingController();

  bool _busy = false;
  bool _loadingFiles = true;
  List<File> _files = const [];

  @override
  void initState() {
    super.initState();
    _reloadFiles();
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reloadFiles() async {
    setState(() => _loadingFiles = true);
    final files = await _service.listBackupFiles();
    if (!mounted) return;
    setState(() {
      _files = files;
      _loadingFiles = false;
    });
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _service.exportToFile();
      await Clipboard.setData(ClipboardData(text: await file.readAsString()));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出成功'),
          content: Text('备份文件：\n${file.path}\n\n备份内容已同时复制到剪贴板，可粘贴到其他设备恢复。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          ],
        ),
      );
      await _reloadFiles();
    } catch (e) {
      if (mounted) _snack('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromFile(File file) async {
    String text;
    try {
      text = await file.readAsString();
    } catch (e) {
      _snack('读取文件失败：$e');
      return;
    }
    await _import(text, p.basename(file.path));
  }

  Future<void> _import(String jsonText, String sourceName) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: Text('导入将覆盖当前全部数据（收纳位置、物件、物资、标签），此操作不可撤销。\n\n确定从「$sourceName」导入吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('导入')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final count = await _service.importAll(jsonText);
      if (!mounted) return;
      _snack('导入完成，共写入 $count 条记录');
    } on FormatException catch (e) {
      if (!mounted) return;
      _snack('导入失败：${e.message}');
    } catch (e) {
      if (!mounted) return;
      _snack('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: _busy
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在处理，请勿退出…'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildExportCard(),
                const SizedBox(height: 12),
                _buildFileImportCard(),
                const SizedBox(height: 12),
                _buildPasteImportCard(),
              ],
            ),
    );
  }

  Widget _buildExportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.file_upload_outlined),
                SizedBox(width: 8),
                Text('全量导出 JSON', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '将全部台账数据（收纳位置、物件、物资、标签）导出为 JSON 备份文件，'
              '保存到应用文档目录的 backups 文件夹，并复制到剪贴板。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导出备份'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileImportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open),
                const SizedBox(width: 8),
                const Text('从备份文件导入', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新列表',
                  onPressed: _reloadFiles,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_loadingFiles)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_files.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '备份目录暂无文件。请先导出生成备份，或使用下方「从 JSON 文本导入」。',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              )
            else
              for (final file in _files)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(p.basename(file.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_fileMeta(file)),
                  onTap: () => _importFromFile(file),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteImportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.content_paste_go),
                SizedBox(width: 8),
                Text('从 JSON 文本导入', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '将备份 JSON 粘贴到下方文本框后导入（例如从其他设备的剪贴板备份恢复）。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pasteController,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '粘贴备份 JSON 文本…',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                final text = _pasteController.text.trim();
                if (text.isEmpty) {
                  _snack('请先粘贴 JSON 内容');
                  return;
                }
                _import(text, '文本框');
              },
              icon: const Icon(Icons.download_for_offline_outlined),
              label: const Text('从文本导入'),
            ),
          ],
        ),
      ),
    );
  }

  String _fileMeta(File file) {
    try {
      final stat = file.statSync();
      final kb = stat.size / 1024;
      return '${formatLocalDateTime(stat.modified)} · ${kb.toStringAsFixed(1)} KB';
    } catch (_) {
      return '';
    }
  }
}

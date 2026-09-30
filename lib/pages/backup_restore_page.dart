import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../service/backup_service.dart';
import '../database/item_service.dart';
import '../database/location_service.dart';
import '../database/supply_service.dart';
import '../service/export_service.dart';
import '../service/expiry_service.dart';
import '../utils/date_utils.dart';

/// 备份与恢复页面
/// v1.1 新增：子集导出（CSV / Markdown 清单，仅导出阅读用，不支持导入）
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final BackupService _service = BackupService();
  final ExportService _exportService = ExportService();
  final TextEditingController _pasteController = TextEditingController();

  // v1.1 子集导出选项
  String _exportType = 'supply'; // supply / item
  bool _exportAsMarkdown = false;

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
                _buildSubsetExportCard(),
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
              '将全部台账数据（收纳位置、物件、物资、标签、模板）导出为 JSON 备份文件，'
              '保存到应用文档目录的 backups 文件夹，并复制到剪贴板。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            // v1.2/v1.3：醒目标注 JSON 备份不含图片
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF9D56E).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.photo_library_outlined, size: 16, color: Color(0xFF8A6D00)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '注意：JSON 备份仅包含文字记录（位置、物件、物资、标签、模板），'
                      '不包含任何图片附件！换机或卸载重装前，请务必手动复制照片文件夹备份'
                      '（位于应用外部存储的 attachments 目录），否则图片会丢失。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8A6D00)),
                    ),
                  ),
                ],
              ),
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

  /// v1.1：子集导出（CSV / Markdown 清单），仅外部阅读用，不能导入回 App
  Future<void> _exportSubset() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final isMd = _exportAsMarkdown;
      late File file;
      late String clipboardText;
      if (_exportType == 'supply') {
        final supplies = await SupplyService().listAll();
        supplies.sort((a, b) => ExpiryService.finalExpireDate(a).compareTo(ExpiryService.finalExpireDate(b)));
        final text = isMd ? _exportService.buildSuppliesMarkdown(supplies) : kUtf8Bom + _exportService.buildSuppliesCsv(supplies);
        file = await _exportService.exportText('supplies', text, isMarkdown: isMd);
        // 剪贴板里不放 BOM
        clipboardText = isMd ? text : text.substring(kUtf8Bom.length);
      } else {
        final items = await ItemService().listAll();
        final locations = await LocationService().listAll();
        final names = {for (final l in locations) if (l.id != null) l.id!: l.name};
        final text = isMd ? _exportService.buildItemsMarkdown(items, locationNames: names) : kUtf8Bom + _exportService.buildItemsCsv(items, locationNames: names);
        file = await _exportService.exportText('items', text, isMarkdown: isMd);
        clipboardText = isMd ? text : text.substring(kUtf8Bom.length);
      }
      await Clipboard.setData(ClipboardData(text: clipboardText));
      if (!mounted) return;
      if (isMd) {
        // v1.2：Markdown 清单支持 App 内预览与复制
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Markdown 清单预览'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: SelectableText(
                  clipboardText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: clipboardText));
                  _snack('已复制全文');
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制'),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ],
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('导出成功'),
            content: Text('清单文件：\n${file.path}\n\n内容已复制到剪贴板。清单仅供外部阅读，不能导入回 App。'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) _snack('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildSubsetExportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.list_alt),
                SizedBox(width: 8),
                Text('清单导出（CSV / Markdown）', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '将物资或物件清单导出为 CSV / Markdown 文件，适合用 Excel、笔记软件等外部工具阅读。'
              '注意：清单不能导入回 App，恢复数据请使用上方的全量 JSON 备份。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'supply', label: Text('物资')),
                      ButtonSegment(value: 'item', label: Text('物件')),
                    ],
                    selected: {_exportType},
                    onSelectionChanged: (s) => setState(() => _exportType = s.first),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('CSV')),
                      ButtonSegment(value: true, label: Text('MD')),
                    ],
                    selected: {_exportAsMarkdown},
                    onSelectionChanged: (s) => setState(() => _exportAsMarkdown = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _exportSubset,
              icon: const Icon(Icons.ios_share),
              label: const Text('导出清单'),
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

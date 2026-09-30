import 'dart:io';

import 'package:path/path.dart' as p;



import '../model/home_supply.dart';
import '../model/stored_item.dart';
import 'expiry_service.dart';
import 'backup_service.dart';

/// v1.1：筛选子集导出服务（CSV / Markdown 清单）。
/// 仅用于外部阅读，不提供导入；全量 JSON 备份仍由 BackupService 负责。
class ExportService {
  final BackupService _backupService = BackupService();

  String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    // 含逗号、引号、换行的字段用引号包裹并转义内部引号
    if (text.contains(RegExp(r'[,"\n\r]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  /// 消耗物资清单行（本地时区展示，与界面一致）
  List<List<Object?>> _supplyRows(List<HomeSupply> supplies) {
    return supplies.map((s) {
      final status = ExpiryService.statusOf(s);
      return <Object?>[
        s.name,
        s.purchaseDate.toLocal().toString().substring(0, 10),
        s.expireDate.toLocal().toString().substring(0, 10),
        s.isOpened ? '是' : '否',
        s.afterOpenDays,
        ExpiryService.finalExpireDate(s).toLocal().toString().substring(0, 10),
        ExpiryService.labelOf(status),
        ExpiryService.describeLeft(s),
        s.note,
      ];
    }).toList();
  }

  String buildSuppliesCsv(List<HomeSupply> supplies) {
    const header = ['名称', '购入日期', '外包装到期', '已开封', '开封后天数', '最终失效', '状态', '剩余/过期', '备注'];
    final buf = StringBuffer(header.map(_csvCell).join(','));
    for (final row in _supplyRows(supplies)) {
      buf.writeln();
      buf.write(row.map(_csvCell).join(','));
    }
    return buf.toString();
  }

  String buildSuppliesMarkdown(List<HomeSupply> supplies) {
    final buf = StringBuffer('# 消耗物资清单\n\n');
    buf.writeln('| 名称 | 购入日期 | 外包装到期 | 已开封 | 开封后天数 | 最终失效 | 状态 | 剩余/过期 | 备注 |');
    buf.writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final row in _supplyRows(supplies)) {
      buf.write('| ');
      buf.write(row.map((c) => (c?.toString() ?? '').replaceAll('|', '\\|')).join(' | '));
      buf.writeln(' |');
    }
    return buf.toString();
  }

  String buildItemsCsv(List<StoredItem> items, {Map<int, String> locationNames = const {}}) {
    const header = ['名称', '数量', '收纳位置', '备注'];
    final buf = StringBuffer(header.map(_csvCell).join(','));
    for (final item in items) {
      final row = <Object?>[
        item.name,
        item.count,
        item.locationId == null ? '未归位' : (locationNames[item.locationId] ?? '未知'),
        item.note,
      ];
      buf.writeln();
      buf.write(row.map(_csvCell).join(','));
    }
    return buf.toString();
  }

  String buildItemsMarkdown(List<StoredItem> items, {Map<int, String> locationNames = const {}}) {
    final buf = StringBuffer('# 普通物件清单\n\n');
    buf.writeln('| 名称 | 数量 | 收纳位置 | 备注 |');
    buf.writeln('| --- | --- | --- | --- |');
    for (final item in items) {
      final location = item.locationId == null ? '未归位' : (locationNames[item.locationId] ?? '未知');
      final row = [item.name, item.count, location, item.note ?? ''];
      buf.write('| ');
      buf.write(row.map((c) => c.toString().replaceAll('|', '\\|')).join(' | '));
      buf.writeln(' |');
    }
    return buf.toString();
  }

  /// 导出文本为 backups 目录下的文件并返回（供页面同时复制剪贴板）
  Future<File> exportText(String fileNamePrefix, String content, {bool isMarkdown = false}) async {
    final dir = await _backupService.backupDirectory();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final ext = isMarkdown ? 'md' : 'csv';
    final file = File(p.join(dir.path, '${fileNamePrefix}_$stamp.$ext'));
    await file.writeAsString(content, flush: true);
    return file;
  }
}

/// UTF-8 BOM：CSV 加上后 Excel 打开才不会中文乱码
const String kUtf8Bom = '\uFEFF';

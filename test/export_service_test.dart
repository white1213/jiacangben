import 'package:flutter_test/flutter_test.dart';

import 'package:jiacangben/model/home_supply.dart';
import 'package:jiacangben/model/stored_item.dart';
import 'package:jiacangben/service/export_service.dart';

void main() {
  final supply = HomeSupply(
    name: '牛奶,鲜奶',
    purchaseDate: DateTime.utc(2026, 9, 1),
    expireDate: DateTime.utc(2026, 10, 20),
    isOpened: true,
    openDate: DateTime.utc(2026, 9, 28),
    afterOpenDays: 7,
    note: '含"有机"认证\n第二行',
  );

  test('CSV：含逗号/引号/换行的字段被正确转义', () {
    final csv = ExportService().buildSuppliesCsv([supply]);
    final lines = csv.split('\n');
    expect(lines.first, '名称,购入日期,外包装到期,已开封,开封后天数,最终失效,状态,剩余/过期,备注');
    expect(csv.contains('"牛奶,鲜奶"'), isTrue);
    expect(csv.contains('""有机""'), isTrue);
  });

  test('Markdown：竖线被转义', () {
    final md = ExportService().buildItemsMarkdown([
      StoredItem(name: '螺|丝', count: 3, locationId: 1, note: 'a|b'),
    ], locationNames: {1: '工具箱'});
    expect(md.contains(r'螺\|丝'), isTrue);
    expect(md.contains(r'a\|b'), isTrue);
    expect(md.contains('工具箱'), isTrue);
    expect(md.contains('| 3 |'), isTrue);
  });
}


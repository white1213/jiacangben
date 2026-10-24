import 'package:flutter_test/flutter_test.dart';

import 'package:jiacangben/model/home_supply.dart';
import 'package:jiacangben/model/stored_item.dart';
import 'package:jiacangben/model/tag_relation.dart';
import 'package:jiacangben/utils/date_utils.dart';

void main() {
  // JSON 备份导入场景：手工编辑过的备份里整数字段可能是 num/double/String 形态
  test('HomeSupply.fromMap 宽松解析整数与布尔字段', () {
    final s = HomeSupply.fromMap({
      'id': 3,
      'name': '牛奶',
      'purchaseDate': '2026-09-01T00:00:00.000Z',
      'expireDate': '2026-10-20T00:00:00.000Z',
      'isOpened': true, // JSON 布尔形态
      'openDate': '2026-09-28T00:00:00.000Z',
      'afterOpenDays': 7.0, // JSON double 形态
      'categoryId': '2', // 字符串形态
    });
    expect(s.id, 3);
    expect(s.isOpened, isTrue);
    expect(s.afterOpenDays, 7);
    expect(s.categoryId, 2);
  });

  test('StoredItem / TagRelation.fromMap 宽松解析', () {
    final item = StoredItem.fromMap({
      'id': 1.0,
      'name': '螺丝',
      'count': '5',
      'locationId': null,
      'categoryId': null,
    });
    expect(item.id, 1);
    expect(item.count, 5);

    final rel = TagRelation.fromMap({'id': 9, 'ownerType': 'supply', 'ownerId': 2.0, 'tagId': 4.0});
    expect(rel.ownerId, 2);
    expect(rel.tagId, 4);
  });

  // v1.5：保质期算式录入
  HomeSupply formula(DateTime prod, int value, ShelfUnit unit) => HomeSupply(
        name: 't',
        purchaseDate: prod,
        expireDate: prod,
        productionDate: prod,
        shelfValue: value,
        shelfUnit: unit,
      );

  test('算式到期日：天/月/年 加法', () {
    expect(
      formula(DateTime(2026, 9, 1), 180, ShelfUnit.day).computeExpireDate(),
      DateTime(2027, 2, 28),
    );
    expect(
      formula(DateTime(2026, 9, 1), 9, ShelfUnit.month).computeExpireDate(),
      DateTime(2027, 6, 1),
    );
    expect(
      formula(DateTime(2026, 9, 1), 2, ShelfUnit.year).computeExpireDate(),
      DateTime(2028, 9, 1),
    );
  });

  test('算式到期日：月末钳制（1-31 + 1月 = 2-28；闰年 = 2-29）', () {
    expect(
      formula(DateTime(2025, 1, 31), 1, ShelfUnit.month).computeExpireDate(),
      DateTime(2025, 2, 28),
    );
    expect(
      formula(DateTime(2024, 1, 31), 1, ShelfUnit.month).computeExpireDate(),
      DateTime(2024, 2, 29),
    );
    // 闰日生产 + 1 年 = 次年 2 月末
    expect(
      formula(DateTime(2024, 2, 29), 1, ShelfUnit.year).computeExpireDate(),
      DateTime(2025, 2, 28),
    );
  });

  test('算式三件套 map 往返；旧备份缺键时为 null 且非算式', () {
    final s = formula(DateTime(2026, 9, 1), 9, ShelfUnit.month);
    final restored = HomeSupply.fromMap(s.toMap());
    expect(restored.hasShelfFormula, isTrue);
    expect(restored.shelfUnit, ShelfUnit.month);
    // 入库统一 UTC（本地午夜即时值）：回读后转本地即得原日期（编辑页预填即此用法）；
    // 到期日按用户可见日期断言（2026-09-01 + 9 月 = 2027-06-01，与时区无关）
    expect(restored.productionDate!.toLocal(), DateTime(2026, 9, 1));
    expect(formatLocalDate(restored.computeExpireDate()), '2027-06-01');

    // v1.4 及之前的备份没有这三列
    final legacy = HomeSupply.fromMap({
      'id': 5,
      'name': '酱油',
      'purchaseDate': '2026-09-01T00:00:00.000Z',
      'expireDate': '2027-03-01T00:00:00.000Z',
      'isOpened': 0,
      'count': 1,
    });
    expect(legacy.hasShelfFormula, isFalse);
    expect(legacy.productionDate, isNull);
    expect(legacy.shelfValue, isNull);
    expect(legacy.shelfUnit, isNull);
  });
}

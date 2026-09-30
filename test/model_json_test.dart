import 'package:flutter_test/flutter_test.dart';

import 'package:jiacangben/model/home_supply.dart';
import 'package:jiacangben/model/stored_item.dart';
import 'package:jiacangben/model/tag_relation.dart';

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
}

import 'package:flutter_test/flutter_test.dart';

import 'package:jiacangben/model/list_filter.dart';

void main() {
  test('ListFilter JSON 往返（含 null 分类与多标签）', () {
    final f = ListFilter(categoryId: 3, tagIds: {1, 5, 9});
    final back = ListFilter.fromJson(f.toJson());
    expect(back.categoryId, 3);
    expect(back.tagIds, {1, 5, 9});
    expect(back.isNotEmpty, isTrue);
  });

  test('旧版 filterJson（仅 status）反序列化为未筛选，向下兼容', () {
    final f = ListFilter.fromJson({'status': 'expiringSoon'});
    expect(f.isEmpty, isTrue);
    expect(f.categoryId, isNull);
    expect(f.tagIds, isEmpty);
  });

  test('宽松解析：double/字符串形态的 id', () {
    final f = ListFilter.fromJson({'categoryId': 2.0, 'tagIds': ['4', 7.0]});
    expect(f.categoryId, 2);
    expect(f.tagIds, {4, 7});
  });

  test('空筛选序列化往返保持为空', () {
    final f = ListFilter();
    expect(ListFilter.fromJson(f.toJson()).isEmpty, isTrue);
  });
}

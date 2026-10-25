import 'package:flutter_test/flutter_test.dart';

import 'package:jiacangben/model/home_supply.dart';
import 'package:jiacangben/service/widget_service.dart';

void main() {
  // v1.6：小部件快照纯函数
  final now = DateTime.utc(2026, 10, 26);

  HomeSupply supply(
    String name,
    DateTime expire, {
    bool opened = false,
    DateTime? openDate,
    int? afterOpenDays,
  }) =>
      HomeSupply(
        name: name,
        purchaseDate: DateTime(2026, 1, 1),
        expireDate: expire,
        isOpened: opened,
        openDate: openDate,
        afterOpenDays: afterOpenDays,
      );

  test('过期置顶 + 临期入选 + 正常排除，按失效时间升序', () {
    final rows = buildWidgetRows(
      [
        supply('正常牛奶', DateTime(2027, 6, 1)), // 正常：排除
        supply('临期酸奶', DateTime(2026, 11, 10)), // 15 天后：临期
        supply('过期面包', DateTime(2026, 10, 20)), // 6 天前：过期
        supply('快过期酱油', DateTime(2026, 11, 24)), // 29 天：临期
      ],
      warnDays: 30,
      now: now,
    );
    expect(rows.map((r) => r.name).toList(), ['过期面包', '临期酸奶', '快过期酱油']);
    expect(rows.first.expired, isTrue);
    expect(rows[1].expired, isFalse);
  });

  test('最多 5 条；开封提前到期参与排序', () {
    final rows = buildWidgetRows(
      [
        // 已开封且开封到期（10-27）早于外包装到期（11-20）→ 最终失效 10-27
        supply('开封果汁', DateTime(2026, 11, 20),
            opened: true, openDate: DateTime(2026, 10, 20), afterOpenDays: 7),
        for (var i = 0; i < 6; i++) supply('临期$i', DateTime(2026, 11, 5).add(Duration(days: i))),
      ],
      warnDays: 30,
      now: now,
    );
    expect(rows.length, 5);
    // 开封果汁 10-27 失效，仅次于已过期的都比它大——排第一
    expect(rows.first.name, '开封果汁');
  });

  test('warnDays 口径生效：窗口外的一天不进名单', () {
    final rows = buildWidgetRows(
      [supply('31天后', DateTime(2026, 11, 26).toUtc())],
      warnDays: 30,
      now: now,
    );
    expect(rows, isEmpty);
  });

  test('toJson 快照字段（原生侧解析契约：n/e/x）', () {
    final rows = buildWidgetRows(
      [supply('过期面包', DateTime(2026, 10, 20))],
      warnDays: 30,
      now: now,
    );
    final json = rows.single.toJson();
    expect(json['n'], '过期面包');
    expect(json['x'], 1);
    expect(json['e'], DateTime(2026, 10, 20).millisecondsSinceEpoch);
  });
}

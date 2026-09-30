import 'package:flutter_test/flutter_test.dart';

import 'package:jiacangben/model/consume_log.dart';

void main() {
  test('ConsumeLog.fromMap 宽松解析（double/String 整数、缺失时间回退）', () {
    final log = ConsumeLog.fromMap({
      'id': 1.0,
      'supplyId': '3',
      'deductCount': 2.0,
      'consumeTime': '2026-09-30T08:00:00.000Z',
      'remark': '吃掉',
    });
    expect(log.id, 1);
    expect(log.supplyId, 3);
    expect(log.deductCount, 2);
    expect(log.consumeTime.isUtc, isTrue);
    expect(log.remark, '吃掉');
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:jiacangben/model/home_supply.dart';
import 'package:jiacangben/service/backup_service.dart';
import 'package:jiacangben/service/expiry_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 30, 8);

  HomeSupply supply({
    required DateTime expire,
    DateTime? openDate,
    int? afterOpenDays,
    bool opened = false,
  }) {
    return HomeSupply(
      name: 't',
      purchaseDate: now,
      expireDate: expire,
      isOpened: opened,
      openDate: openDate,
      afterOpenDays: afterOpenDays,
    );
  }

  group('到期计算', () {
    test('未开封、剩余 > 30 天为正常', () {
      final s = supply(expire: now.add(const Duration(days: 31)));
      expect(ExpiryService.statusOf(s, now: now), ExpiryStatus.normal);
    });

    test('剩余恰好 30 天（<= 阈值）为临期', () {
      final s = supply(expire: now.add(const Duration(days: 30)));
      expect(ExpiryService.statusOf(s, now: now), ExpiryStatus.expiringSoon);
    });

    test('失效时间早于当前时间为已过期', () {
      final s = supply(expire: now.subtract(const Duration(days: 1)));
      expect(ExpiryService.statusOf(s, now: now), ExpiryStatus.expired);
    });

    test('已开封且字段齐全：最终失效 = min(外包装, 开封日期 + 天数)', () {
      final s = supply(
        expire: now.add(const Duration(days: 100)),
        opened: true,
        openDate: now.subtract(const Duration(days: 10)),
        afterOpenDays: 15,
      );
      // 开封到期 = now - 10天 + 15天 = now + 5天，早于外包装到期
      expect(ExpiryService.finalExpireDate(s), now.add(const Duration(days: 5)));
      expect(ExpiryService.statusOf(s, now: now), ExpiryStatus.expiringSoon);
    });

    test('外包装到期更早时以外包装为准', () {
      final s = supply(
        expire: now.add(const Duration(days: 3)),
        opened: true,
        openDate: now.subtract(const Duration(days: 1)),
        afterOpenDays: 365,
      );
      expect(ExpiryService.finalExpireDate(s), now.add(const Duration(days: 3)));
    });

    test('未开封时忽略开封日期与天数', () {
      final s = supply(
        expire: now.add(const Duration(days: 60)),
        opened: false,
        openDate: now,
        afterOpenDays: 1,
      );
      expect(ExpiryService.finalExpireDate(s), now.add(const Duration(days: 60)));
      expect(ExpiryService.statusOf(s, now: now), ExpiryStatus.normal);
    });
  });

  group('备份校验', () {
    test('非法 JSON 抛 FormatException', () {
      expect(() => BackupService().validate('not json'), throwsFormatException);
    });

    test('缺少必备字段抛 FormatException', () {
      expect(() => BackupService().validate('{"a": 1}'), throwsFormatException);
      expect(
        () => BackupService().validate('{"storageLocation": [], "storedItem": [], "tag": [], "tagRelation": []}'),
        throwsFormatException,
      );
    });
  });
}

import '../consts.dart';
import '../model/home_supply.dart';
import '../utils/date_utils.dart';

/// 到期状态
enum ExpiryStatus { normal, expiringSoon, expired }

/// 到期计算服务（纯前台内存计算，无任何后台任务）
class ExpiryService {
  const ExpiryService._();

  /// 最终失效时间 = min(外包装到期, 开封到期)
  /// 开封到期 = openDate + afterOpenDays，仅当已开封且开封日期、天数齐全时参与计算
  static DateTime finalExpireDate(HomeSupply supply) {
    if (supply.hasOpenExpire) {
      final openExpire = supply.openDate!.add(Duration(days: supply.afterOpenDays!));
      return supply.expireDate.isBefore(openExpire) ? supply.expireDate : openExpire;
    }
    return supply.expireDate;
  }

  /// 已过期：失效时间 < 当前时间；
  /// 临期：失效时间距当前 <= [warnDays] 天（默认取 consts 的 30，可在设置页自定义）
  static ExpiryStatus statusOf(HomeSupply supply, {DateTime? now, int? warnDays}) {
    final n = (now ?? utcNow());
    final expire = finalExpireDate(supply);
    if (expire.isBefore(n)) return ExpiryStatus.expired;
    final threshold = warnDays ?? kExpiringSoonDays;
    if (!expire.isAfter(n.add(Duration(days: threshold)))) {
      return ExpiryStatus.expiringSoon;
    }
    return ExpiryStatus.normal;
  }

  /// 相对天数（本地展示用）：正数=剩余天数（向下取整），负数=已过期天数（向上取整），0=当日到期
  static int daysLeft(HomeSupply supply, {DateTime? now}) {
    final n = now ?? utcNow();
    final diff = finalExpireDate(supply).difference(n);
    if (diff.isNegative) {
      final overdue = -diff;
      return -(overdue.inDays + (overdue.inSeconds % Duration.secondsPerDay == 0 ? 0 : 1));
    }
    return diff.inDays;
  }

  /// 状态中文文案
  static String labelOf(ExpiryStatus status) {
    switch (status) {
      case ExpiryStatus.expired:
        return '已过期';
      case ExpiryStatus.expiringSoon:
        return '临期';
      case ExpiryStatus.normal:
        return '正常';
    }
  }

  /// 预警描述：如「剩余 12 天」「今天到期」「已过期 3 天」
  static String describeLeft(HomeSupply supply, {DateTime? now}) {
    final days = daysLeft(supply, now: now);
    if (days < 0) return '已过期 ${-days} 天';
    if (days == 0) return '今天到期';
    return '剩余 $days 天';
  }
}

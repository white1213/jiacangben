import '../model/home_supply.dart';
import '../model/stored_item.dart';
import '../service/expiry_service.dart';

/// v1.4：列表排序选项（key 与 ListFilter.sortBy 序列化值一致）
/// (key, 显示文案, 是否仅消耗物资列表有效)
const List<(String, String, bool)> kListSortOptions = [
  ('entryOrder', '录入顺序', false),
  ('nameAsc', '按名称 A-Z', false),
  ('nameDesc', '按名称 Z-A', false),
  ('countAsc', '按数量升序', false),
  ('countDesc', '按数量降序', false),
  ('expireAsc', '到期时间升序', true),
];

/// 排序 key -> 显示文案
String sortLabel(String key) {
  for (final (k, label, _) in kListSortOptions) {
    if (k == key) return label;
  }
  return '录入顺序';
}

/// 消耗物资列表排序（sortBy 取 kListSortOptions 的 key；未知值回退录入顺序）
void sortSupplies(List<HomeSupply> list, String sortBy) {
  switch (sortBy) {
    case 'nameAsc':
      list.sort((a, b) => a.name.compareTo(b.name));
    case 'nameDesc':
      list.sort((a, b) => b.name.compareTo(a.name));
    case 'countAsc':
      list.sort((a, b) => a.count.compareTo(b.count));
    case 'countDesc':
      list.sort((a, b) => b.count.compareTo(a.count));
    case 'expireAsc':
      list.sort((a, b) => ExpiryService.finalExpireDate(a).compareTo(ExpiryService.finalExpireDate(b)));
    default:
      // 录入顺序 = 插入先后（id 升序）
      list.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
  }
}

/// 普通物件列表排序（无到期时间项）
void sortStoredItems(List<StoredItem> list, String sortBy) {
  switch (sortBy) {
    case 'nameAsc':
      list.sort((a, b) => a.name.compareTo(b.name));
    case 'nameDesc':
      list.sort((a, b) => b.name.compareTo(a.name));
    case 'countAsc':
      list.sort((a, b) => a.count.compareTo(b.count));
    case 'countDesc':
      list.sort((a, b) => b.count.compareTo(a.count));
    default:
      list.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
  }
}

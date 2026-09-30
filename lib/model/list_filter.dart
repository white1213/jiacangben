/// v1.3/v1.4：列表筛选 + 排序条件（分类 + 标签集合 + 排序方式）。
/// 供筛选弹窗、SavedFilter 序列化、激活筛选持久化共用；不涉及任何表结构变更。
class ListFilter {
  /// v1.4：排序方式（entryOrder / nameAsc / nameDesc / countAsc / countDesc / expireAsc）
  String sortBy;

  int? categoryId; // null = 不筛选分类
  Set<int> tagIds; // 空 = 不筛选标签；非空 = OR 语义（任一命中即匹配）

  ListFilter({this.categoryId, Set<int>? tagIds, this.sortBy = 'entryOrder'}) : tagIds = tagIds ?? {};

  /// 是否激活了筛选条件（供列表页 Badge 高亮；排序不算筛选）
  bool get isFiltered => categoryId != null || tagIds.isNotEmpty;

  /// 兼容保留：与 isFiltered 等价（排序不参与判断）
  bool get isEmpty => categoryId == null && tagIds.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// 序列化到 SavedFilter.filterJson / SharedPreferences（含排序配置）
  Map<String, dynamic> toJson() => {
        'categoryId': categoryId,
        'tagIds': tagIds.toList(),
        'sortBy': sortBy,
      };

  /// 宽松反序列化：缺失键视为未筛选/录入顺序，兼容旧版只存 status 的 filterJson
  factory ListFilter.fromJson(Map<String, dynamic> json) {
    final rawCategory = json['categoryId'];
    final rawTags = json['tagIds'];
    final rawSort = json['sortBy'];
    return ListFilter(
      categoryId: rawCategory is num ? rawCategory.toInt() : (rawCategory is String ? int.tryParse(rawCategory) : null),
      tagIds: rawTags is List ? rawTags.map((e) => e is num ? e.toInt() : int.tryParse(e.toString())).whereType<int>().toSet() : {},
      sortBy: rawSort is String && rawSort.isNotEmpty ? rawSort : 'entryOrder',
    );
  }
}

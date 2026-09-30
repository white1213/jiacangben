/// v1.3：列表筛选条件（分类 + 标签集合）。
/// 供筛选弹窗、SavedFilter 序列化、激活筛选持久化共用；不涉及任何表结构变更。
class ListFilter {
  int? categoryId; // null = 不筛选分类
  Set<int> tagIds; // 空 = 不筛选标签；非空 = OR 语义（任一命中即匹配）

  ListFilter({this.categoryId, Set<int>? tagIds}) : tagIds = tagIds ?? {};

  bool get isEmpty => categoryId == null && tagIds.isEmpty;

  /// 是否存在激活的筛选条件（供列表页 Badge 高亮）
  bool get isNotEmpty => !isEmpty;

  /// 序列化到 SavedFilter.filterJson / SharedPreferences
  Map<String, dynamic> toJson() => {
        'categoryId': categoryId,
        'tagIds': tagIds.toList(),
      };

  /// 宽松反序列化：缺失键视为未筛选，兼容旧版只存 status 的 filterJson
  factory ListFilter.fromJson(Map<String, dynamic> json) {
    final rawCategory = json['categoryId'];
    final rawTags = json['tagIds'];
    return ListFilter(
      categoryId: rawCategory is num ? rawCategory.toInt() : (rawCategory is String ? int.tryParse(rawCategory) : null),
      tagIds: rawTags is List ? rawTags.map((e) => e is num ? e.toInt() : int.tryParse(e.toString())).whereType<int>().toSet() : {},
    );
  }
}

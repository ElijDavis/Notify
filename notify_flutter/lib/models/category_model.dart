class Category {
  final String id;
  final String name;
  final int colorValue;
  final String? parentCategoryId; // Null = Main Category, String = Subcategory
  final String? shareCode;

  Category({
    required this.id,
    required this.name,
    this.colorValue = 0xFF9E9E9E, // Default Grey
    this.parentCategoryId,
    this.shareCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color_value': colorValue,
      'parent_category_id': parentCategoryId,
      'share_code': shareCode,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      colorValue: map['color_value'] ?? 0xFF9E9E9E,
      parentCategoryId: map['parent_category_id'],
      shareCode: map['share_code'],
    );
  }
}
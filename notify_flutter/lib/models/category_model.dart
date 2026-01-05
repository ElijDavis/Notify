class Category {
  final String id;
  final String name;
  final int colorValue;
  final String? parentCategoryId; // Null = Main Category, String = Subcategory

  Category({
    required this.id,
    required this.name,
    this.colorValue = 0xFF9E9E9E, // Default Grey
    this.parentCategoryId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color_value': colorValue,
      'parent_category_id': parentCategoryId,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      colorValue: map['color_value'] ?? 0xFF9E9E9E,
      parentCategoryId: map['parent_category_id'],
    );
  }
}
class MealOption {
  final String menuId;
  final String menuName;
  final String description;
  final String status; // ordered, available, cancelled, none
  final String locationId;
  final String mealType; // 'malica', 'kosilo', etc. — parsed from HTML

  const MealOption({
    required this.menuId,
    required this.menuName,
    required this.description,
    required this.status,
    required this.locationId,
    this.mealType = 'malica',
  });

  @override
  String toString() =>
      'MealOption($menuName, status=$status, desc="${description.length > 40 ? '${description.substring(0, 40)}...' : description}")';
}

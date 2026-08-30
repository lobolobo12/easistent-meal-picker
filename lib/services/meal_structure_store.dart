import 'package:flutter/foundation.dart' show listEquals;

import '../models/meal_option.dart';
import 'app_files.dart';

/// Stores the detected meal structure for the current school.
///
/// Structure includes the meal type (malica, kosilo, etc.) and the ordered
/// list of menu names the school offers. Detected from the meal page HTML on
/// each menu fetch, saved locally, and used by the settings screen to
/// populate the menu ranking list.
class MealStructureStore {
  static const _file = JsonFile(AppFiles.mealStructure);

  static const _defaults = {'meal_type': 'malica', 'menu_names': <String>[]};

  static Future<Map<String, dynamic>> load() async {
    final data = await _file.readMap();
    return data.isEmpty ? Map<String, dynamic>.from(_defaults) : data;
  }

  static Future<void> save(Map<String, dynamic> data) => _file.write(data);

  /// Detect meal structure from parsed menu data and save if it changed.
  static Future<void> detectAndSave(Map<String, List<MealOption>> menu) async {
    if (menu.isEmpty) return;

    // Meal type comes from the first option the school actually serves.
    var mealType = 'malica';
    for (final options in menu.values) {
      if (options.isNotEmpty) {
        mealType = options.first.mealType;
        break;
      }
    }

    // Use the day with the most options for the fullest menu name list.
    var bestDay = <MealOption>[];
    for (final options in menu.values) {
      if (options.length > bestDay.length) bestDay = options;
    }
    final seen = <String>{};
    final menuNames = <String>[
      for (final opt in bestDay)
        if (opt.menuName.isNotEmpty && seen.add(opt.menuName)) opt.menuName,
    ];

    final stored = await load();
    final storedNames = List<String>.from(stored['menu_names'] ?? const []);
    final storedType = stored['meal_type'] as String? ?? 'malica';

    if (mealType != storedType || !listEquals(menuNames, storedNames)) {
      await save({'meal_type': mealType, 'menu_names': menuNames});
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/meal_option.dart';

/// Stores the detected meal structure for the current school.
///
/// Structure includes the meal type (malica, kosilo, etc.) and the ordered
/// list of menu names the school offers. Detected from /prehrana HTML on
/// each menu fetch, saved locally, and used by the settings screen to
/// populate the menu ranking list.
class MealStructureStore {
  static File? _cachedFile;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/meal_structure.json');
    return _cachedFile!;
  }

  static Future<Map<String, dynamic>> load() async {
    final file = await _getFile();
    if (file.existsSync()) {
      try {
        return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {'meal_type': 'malica', 'menu_names': <String>[]};
  }

  static Future<void> save(Map<String, dynamic> data) async {
    final file = await _getFile();
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data));
  }

  /// Detect meal structure from parsed menu data and save if changed.
  static Future<void> detectAndSave(
      Map<String, List<MealOption>> menu) async {
    if (menu.isEmpty) return;

    // Detect meal type from first available option
    var mealType = 'malica';
    for (final options in menu.values) {
      if (options.isNotEmpty) {
        mealType = options.first.mealType;
        break;
      }
    }

    // Use the day with the most options for the fullest menu name list
    var bestDay = <MealOption>[];
    for (final options in menu.values) {
      if (options.length > bestDay.length) bestDay = options;
    }
    final menuNames = <String>[
      for (final opt in bestDay)
        if (opt.menuName.isNotEmpty) opt.menuName,
    ];
    // Deduplicate while preserving order
    final seen = <String>{};
    menuNames.retainWhere((n) => seen.add(n));

    // Only write if changed
    final stored = await load();
    final storedNames = List<String>.from(stored['menu_names'] ?? []);
    final storedType = stored['meal_type'] as String? ?? 'malica';

    if (mealType != storedType || !_listEquals(menuNames, storedNames)) {
      await save({'meal_type': mealType, 'menu_names': menuNames});
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

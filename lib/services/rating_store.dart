import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent storage for meal ratings (1-5 stars per day).
///
/// Each entry: {date, menuName, description, rating, ratedAt}
class RatingStore {
  static File? _cachedFile;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/meal_ratings.json');
    return _cachedFile!;
  }

  /// Load all ratings. Returns empty list if no file exists.
  static Future<List<Map<String, dynamic>>> load() async {
    final file = await _getFile();
    if (!file.existsSync()) return [];
    try {
      final data = jsonDecode(await file.readAsString()) as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Add a rating and save to disk.
  static Future<void> add(Map<String, dynamic> entry) async {
    final ratings = await load();
    // Replace existing rating for same date if any
    ratings.removeWhere((r) => r['date'] == entry['date']);
    ratings.add(entry);
    final file = await _getFile();
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(ratings));
  }

  /// Check if today has already been rated.
  static Future<bool> hasRatingForDate(String date) async {
    final ratings = await load();
    return ratings.any((r) => r['date'] == date);
  }
}

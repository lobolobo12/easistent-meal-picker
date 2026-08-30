import 'app_files.dart';

/// Persistent storage for meal ratings (1-5 stars per day).
///
/// Each entry: {date, menuName, description, rating, ratedAt}
class RatingStore {
  static const _file = JsonFile(AppFiles.ratings);

  /// Load all ratings. Returns an empty list if no file exists.
  static Future<List<Map<String, dynamic>>> load() => _file.readList();

  /// Add a rating and save to disk. One rating per date; newest wins.
  static Future<void> add(Map<String, dynamic> entry) async {
    final ratings = await load();
    ratings.removeWhere((r) => r['date'] == entry['date']);
    ratings.add(entry);
    await _file.write(ratings);
  }

  /// Check if a date has already been rated.
  static Future<bool> hasRatingForDate(String date) async {
    final ratings = await load();
    return ratings.any((r) => r['date'] == date);
  }
}

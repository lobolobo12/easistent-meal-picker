import 'app_files.dart';

/// Persistent storage for absence date ranges.
///
/// Each entry: {from, to} where both are "YYYY-MM-DD" strings (inclusive).
class AbsenceStore {
  static const _file = JsonFile(AppFiles.absences);

  /// Load all absence ranges.
  static Future<List<Map<String, dynamic>>> load() => _file.readList();

  /// Add an absence range and save.
  static Future<void> add(String from, String to) async {
    final ranges = await load();
    ranges.add({'from': from, 'to': to});
    await _file.write(ranges);
  }

  /// Check if a date falls within any absence range.
  static Future<bool> isAbsent(String date) async =>
      isAbsentSync(await load(), date);

  /// Synchronous check against a pre-loaded list of ranges.
  static bool isAbsentSync(List<Map<String, dynamic>> ranges, String date) {
    for (final r in ranges) {
      final from = r['from'] as String? ?? '';
      final to = r['to'] as String? ?? '';
      if (from.isEmpty || to.isEmpty) continue;
      if (date.compareTo(from) >= 0 && date.compareTo(to) <= 0) return true;
    }
    return false;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent storage for absence date ranges.
///
/// Each entry: {from, to} where both are "YYYY-MM-DD" strings (inclusive).
class AbsenceStore {
  static File? _cachedFile;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/absences.json');
    return _cachedFile!;
  }

  /// Load all absence ranges.
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

  /// Add an absence range and save.
  static Future<void> add(String from, String to) async {
    final ranges = await load();
    ranges.add({'from': from, 'to': to});
    final file = await _getFile();
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(ranges));
  }

  /// Check if a date falls within any absence range.
  static Future<bool> isAbsent(String date) async {
    final ranges = await load();
    return isAbsentSync(ranges, date);
  }

  /// Synchronous check against a pre-loaded list of ranges.
  static bool isAbsentSync(List<Map<String, dynamic>> ranges, String date) {
    for (final r in ranges) {
      final from = r['from'] as String? ?? '';
      final to = r['to'] as String? ?? '';
      if (date.compareTo(from) >= 0 && date.compareTo(to) <= 0) return true;
    }
    return false;
  }
}

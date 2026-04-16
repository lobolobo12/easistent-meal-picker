import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent record of probe reverts that failed mid-flight.
///
/// `_probeLockedDays` picks a non-ordered menu and calls `selectMeal`
/// to detect a lock; if the server accepts, it must revert to the
/// original selection. If that revert fails (network drop, app killed),
/// the user's selection is left on the probe option. Each such failure
/// is persisted here so the next probe run can retry the revert before
/// anything else happens.
///
/// Each entry:
///   {
///     "date": "YYYY-MM-DD",
///     "probeMenuId": "123",
///     "revertToMenuId": "456" | null,  // null => cancel the probe
///     "locationId": "15856",
///     "mealType": "malica",
///     "recordedAt": "ISO-8601"
///   }
class PendingRevertStore {
  static File? _cachedFile;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/pending_reverts.json');
    return _cachedFile!;
  }

  /// Load all pending reverts. Empty list on missing/corrupt file.
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

  /// Record a failed revert. Deduplicates by date (newest wins).
  static Future<void> add(Map<String, dynamic> entry) async {
    final list = await load();
    list.removeWhere((e) => e['date'] == entry['date']);
    list.add(entry);
    await saveAll(list);
  }

  /// Replace the entire store. Deletes the file if empty.
  static Future<void> saveAll(List<Map<String, dynamic>> list) async {
    final file = await _getFile();
    if (list.isEmpty) {
      if (file.existsSync()) await file.delete();
      return;
    }
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(list));
  }
}

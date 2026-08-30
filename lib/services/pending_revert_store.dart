import 'app_files.dart';

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
  static const _file = JsonFile(AppFiles.pendingReverts);

  /// Load all pending reverts. Empty list on missing/corrupt file.
  static Future<List<Map<String, dynamic>>> load() => _file.readList();

  /// Record a failed revert. Deduplicates by date (newest wins).
  static Future<void> add(Map<String, dynamic> entry) async {
    final list = await load();
    list.removeWhere((e) => e['date'] == entry['date']);
    list.add(entry);
    await saveAll(list);
  }

  /// Replace the entire store. Deletes the file when empty.
  static Future<void> saveAll(List<Map<String, dynamic>> list) async {
    if (list.isEmpty) return _file.delete();
    return _file.write(list);
  }
}

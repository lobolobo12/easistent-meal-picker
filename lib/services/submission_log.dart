import 'app_files.dart';

/// Persistent log of submitted meal selections.
/// Seeds from the bundled asset on first use, then reads/writes the local file.
class SubmissionLog {
  static const _file =
      JsonFile(AppFiles.submissionLog, seedAsset: 'assets/submission_log.json');

  /// Load all log entries. Copies from the bundled asset on first launch so
  /// history carries across a reinstall or a move to another platform.
  static Future<List<Map<String, dynamic>>> load() => _file.readListOrSeed();

  /// Append a single submission entry and save.
  static Future<void> add(Map<String, dynamic> entry) async {
    final log = await load();
    log.add(entry);
    await _file.write(log);
  }

  /// Clear the entire log.
  static Future<void> clear() => _file.delete();
}

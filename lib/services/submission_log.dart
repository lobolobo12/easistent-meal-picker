import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent log of submitted meal selections.
class SubmissionLog {
  static File? _cachedFile;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/submission_log.json');
    return _cachedFile!;
  }

  /// Load all log entries. Returns empty list if no log exists.
  static Future<List<Map<String, dynamic>>> load() async {
    final file = await _getFile();
    if (!file.existsSync()) return [];
    final data = jsonDecode(await file.readAsString()) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  /// Append a single submission entry and save.
  static Future<void> add(Map<String, dynamic> entry) async {
    final log = await load();
    log.add(entry);
    final file = await _getFile();
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(log));
  }

  /// Clear the entire log.
  static Future<void> clear() async {
    final file = await _getFile();
    if (file.existsSync()) await file.delete();
  }
}

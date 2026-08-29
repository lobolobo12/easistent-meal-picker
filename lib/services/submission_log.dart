import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Persistent log of submitted meal selections.
/// Seeds from the bundled asset on first use, then reads/writes local file.
class SubmissionLog {
  static File? _cachedFile;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/submission_log.json');
    return _cachedFile!;
  }

  /// Load all log entries. Copies from the bundled asset on first launch so
  /// history carries across a reinstall or a move to another platform.
  static Future<List<Map<String, dynamic>>> load() async {
    final file = await _getFile();
    if (file.existsSync()) {
      final data = jsonDecode(await file.readAsString()) as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    }
    try {
      final assetStr = await rootBundle.loadString('assets/submission_log.json');
      await file.writeAsString(assetStr);
      return (jsonDecode(assetStr) as List<dynamic>)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      // No seed asset bundled — start empty.
      return [];
    }
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

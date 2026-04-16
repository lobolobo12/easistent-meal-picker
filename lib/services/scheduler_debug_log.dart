import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Append-only debug log written from any isolate — main or background.
///
/// Each entry is one line: `ISO-8601 | source | message`. Keeps the file
/// below ~100 KB by trimming oldest lines when it grows too large.
///
/// Use this to confirm that alarm callbacks actually fire on device:
/// after an install, wait for the scheduled time, then open the app and
/// read the log via `SchedulerDebugLog.read()`.
class SchedulerDebugLog {
  static File? _cachedFile;
  static const _maxBytes = 100 * 1024;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/scheduler_debug.log');
    return _cachedFile!;
  }

  /// Append a line to the log. Non-throwing — debug logging must never
  /// break a production code path.
  static Future<void> log(String source, String message) async {
    try {
      final file = await _getFile();
      final stamp = DateTime.now().toIso8601String();
      final line = '$stamp | $source | $message\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
      // Trim if the file has grown past the cap.
      final length = await file.length();
      if (length > _maxBytes) {
        final content = await file.readAsString();
        // Keep the last ~75% of the file (rough trim to a newline boundary).
        final keepFrom = (content.length * 0.25).round();
        final nl = content.indexOf('\n', keepFrom);
        final trimmed = nl > 0 ? content.substring(nl + 1) : content;
        await file.writeAsString(trimmed, flush: true);
      }
    } catch (_) {
      // Swallow — debug logging must be invisible on failure.
    }
  }

  /// Read the full log. Returns the empty string if no log file exists.
  static Future<String> read() async {
    try {
      final file = await _getFile();
      if (!file.existsSync()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _getFile();
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }
}

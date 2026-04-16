import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Persistent storage for user preferences (keywords, menu ranking).
/// Seeds from the bundled asset on first use, then reads/writes local file.
class PreferencesStore {
  static File? _cachedFile;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/preferences.json');
    return _cachedFile!;
  }

  static Future<Map<String, dynamic>> load() async {
    final file = await _getFile();
    if (file.existsSync()) {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
    // First launch: seed from bundled asset
    final assetStr = await rootBundle.loadString('assets/preferences.json');
    await file.writeAsString(assetStr);
    return jsonDecode(assetStr) as Map<String, dynamic>;
  }

  static Future<void> save(Map<String, dynamic> data) async {
    final file = await _getFile();
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data));
  }
}

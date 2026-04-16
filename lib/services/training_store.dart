import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Persistent storage for training data.
/// Seeds from the bundled asset on first use, then reads/writes local file.
class TrainingStore {
  static File? _cachedFile;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/training_data.json');
    return _cachedFile!;
  }

  /// Load all training data. Copies from asset on first launch.
  static Future<List<dynamic>> load() async {
    final file = await _getFile();
    if (file.existsSync()) {
      return jsonDecode(await file.readAsString()) as List<dynamic>;
    }
    // First launch: seed from bundled asset
    final assetStr = await rootBundle.loadString('assets/training_data.json');
    await file.writeAsString(assetStr);
    return jsonDecode(assetStr) as List<dynamic>;
  }

  /// Save the full training data list to disk.
  static Future<void> save(List<dynamic> data) async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode(data));
  }
}

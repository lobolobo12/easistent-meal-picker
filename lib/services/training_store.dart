import 'app_files.dart';

/// Persistent storage for training data.
/// Seeds from the bundled asset on first use, then reads/writes the local file.
class TrainingStore {
  static const _file = JsonFile(AppFiles.trainingData,
      seedAsset: 'assets/training_data.json');

  /// Load all training data. Copies from the asset on first launch.
  /// Returns an empty list rather than throwing when the file is unreadable.
  static Future<List<dynamic>> load() async {
    final data = await _file.readOrSeed();
    return data is List ? data : <dynamic>[];
  }

  /// Save the full training data list to disk.
  static Future<void> save(List<dynamic> data) => _file.write(data);
}

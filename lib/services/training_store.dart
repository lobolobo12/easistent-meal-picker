import '../util/training_data.dart';
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
    if (data is! List) return <dynamic>[];
    // Collapse on read so existing devices carrying triplicated rows are
    // migrated the first time anything asks for the data.
    return collapseDuplicates(data);
  }

  /// Save the full training data list to disk, collapsed first.
  static Future<void> save(List<dynamic> data) =>
      _file.write(collapseDuplicates(data));

  /// Fold duplicate rows into weights. See [collapseTrainingDuplicates].
  static List<dynamic> collapseDuplicates(List<dynamic> data) =>
      collapseTrainingDuplicates(data);
}

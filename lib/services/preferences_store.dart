import 'app_files.dart';

/// Persistent storage for user preferences (keywords, menu ranking).
/// Seeds from the bundled asset on first use, then reads/writes the local file.
class PreferencesStore {
  static const _file =
      JsonFile(AppFiles.preferences, seedAsset: 'assets/preferences.json');

  static Future<Map<String, dynamic>> load() => _file.readMapOrSeed();

  static Future<void> save(Map<String, dynamic> data) => _file.write(data);
}

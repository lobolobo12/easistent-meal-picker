import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Every file the app persists, named exactly once.
///
/// Before this existed the same literals were repeated across the stores and
/// the scheduler — `submission_log.json` in four places, `credentials.json`
/// in three. The background alarm reads those files directly (it cannot
/// always reach a platform channel to go through a store), so a typo in one
/// copy broke the unattended Monday submit silently, at 18:00, with nobody
/// watching. One constant each removes that failure mode.
class AppFiles {
  static const trainingData = 'training_data.json';
  static const preferences = 'preferences.json';
  static const submissionLog = 'submission_log.json';
  static const ratings = 'meal_ratings.json';
  static const absences = 'absences.json';
  static const pendingReverts = 'pending_reverts.json';
  static const mealStructure = 'meal_structure.json';
  static const credentials = 'credentials.json';

  static const onboardingComplete = 'onboarding_complete.txt';
  static const autoSubmitMarker = 'autosubmit_marker.txt';
  static const menuAvailableMarker = 'menu_available_marker.txt';
  static const ratingNotifiedMarker = 'rating_notified_marker.txt';

  static Directory? _dir;

  /// The app-private documents directory, resolved once per isolate.
  static Future<Directory> dir() async =>
      _dir ??= await getApplicationDocumentsDirectory();

  static Future<File> file(String name) async =>
      File('${(await dir()).path}/$name');

  /// Test seam: point the whole app at a temp directory.
  static void overrideDirForTesting(Directory? d) => _dir = d;
}

/// A JSON document on disk, with the three properties every store here needs
/// and none of them previously had all of: atomic writes, recovery from a
/// corrupt file, and optional first-launch seeding from a bundled asset.
class JsonFile {
  /// Filename inside the documents directory — an [AppFiles] constant.
  final String name;

  /// Bundled asset to seed from on first launch, e.g. `assets/preferences.json`.
  final String? seedAsset;

  const JsonFile(this.name, {this.seedAsset});

  Future<File> resolve() => AppFiles.file(name);

  /// Decode the document, or return null when it is absent, unreadable, or
  /// not valid JSON.
  ///
  /// A corrupt file is renamed to `<name>.corrupt` rather than deleted. The
  /// old code let the exception escape, so a half-written training file — the
  /// exact thing a killed background alarm produces — crashed the app on the
  /// next launch with no way back. Quarantining recovers the app without
  /// throwing away data the user might want to salvage.
  Future<Object?> read() async {
    final file = await resolve();
    if (!file.existsSync()) return null;
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return jsonDecode(text);
    } catch (_) {
      await _quarantine(file);
      return null;
    }
  }

  /// Read, falling back to the bundled seed asset on first launch.
  ///
  /// The seed is written to disk so it only costs a bundle read once, and so
  /// the background isolate — which has no asset bundle — finds a real file.
  Future<Object?> readOrSeed() async {
    final existing = await read();
    if (existing != null) return existing;
    final asset = seedAsset;
    if (asset == null) return null;
    try {
      final text = await rootBundle.loadString(asset);
      final decoded = jsonDecode(text);
      await write(decoded);
      return decoded;
    } catch (_) {
      // No seed bundled, or it is itself malformed — start empty.
      return null;
    }
  }

  /// Write [data] atomically: encode to a sibling temp file, then rename.
  ///
  /// `rename` within a directory is atomic on both APFS and ext4, so a reader
  /// (or the next launch after a kill) sees either the old document or the
  /// new one, never a truncated prefix. This matters most for the background
  /// alarm, which Android may kill at any point during its write.
  Future<void> write(Object? data) async {
    final file = await resolve();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  Future<void> delete() async {
    final file = await resolve();
    if (file.existsSync()) await file.delete();
  }

  Future<bool> exists() async => (await resolve()).existsSync();

  static Future<void> _quarantine(File file) async {
    try {
      await file.rename('${file.path}.corrupt');
    } catch (_) {
      // Quarantine is best-effort; returning null already unblocks the app.
    }
  }
}

/// Convenience wrappers for the shape each store actually stores.
extension JsonFileShapes on JsonFile {
  /// Decode as a list of maps, tolerating anything unexpected.
  Future<List<Map<String, dynamic>>> readList() async {
    final data = await read();
    return _asList(data);
  }

  Future<List<Map<String, dynamic>>> readListOrSeed() async {
    final data = await readOrSeed();
    return _asList(data);
  }

  Future<Map<String, dynamic>> readMap() async {
    final data = await read();
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> readMapOrSeed() async {
    final data = await readOrSeed();
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _asList(Object? data) {
    if (data is! List) return [];
    return [
      for (final e in data)
        if (e is Map<String, dynamic>) e,
    ];
  }
}

/// A one-line marker file (`autosubmit_marker.txt` and friends), used to make
/// the scheduler handlers idempotent.
class MarkerFile {
  final String name;
  const MarkerFile(this.name);

  Future<String?> read() async {
    try {
      final file = await AppFiles.file(name);
      if (!file.existsSync()) return null;
      return (await file.readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  Future<bool> matches(String value) async => (await read()) == value;

  Future<void> write(String value) async {
    final file = await AppFiles.file(name);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    await tmp.rename(file.path);
  }

  Future<void> delete() async {
    final file = await AppFiles.file(name);
    if (file.existsSync()) await file.delete();
  }
}

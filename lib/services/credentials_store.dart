import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent encrypted storage for eAsistent login credentials.
///
/// Primary store: flutter_secure_storage (Android KeyStore / iOS Keychain).
/// Background fallback: plain JSON file in app-private directory, used only
/// by background isolates (alarm manager) that lack platform channel access.
/// The file is in the app sandbox (not world-readable) and Android's
/// file-based encryption protects it at rest.
class CredentialsStore {
  static const _storage = FlutterSecureStorage();
  static const _keyUser = 'ea_username';
  static const _keyPass = 'ea_password';

  /// Load saved credentials (foreground only).
  static Future<({String username, String password})?> load() async {
    try {
      final user = await _storage.read(key: _keyUser);
      final pass = await _storage.read(key: _keyPass);
      if (user != null && pass != null && user.isNotEmpty) {
        return (username: user, password: pass);
      }
    } catch (_) {
      // Fall through to file-based fallback
    }
    // Try fallback file (migration from old plain-text storage)
    return _loadFromFile();
  }

  /// Save credentials to encrypted storage + background fallback file.
  static Future<void> save(String username, String password) async {
    await _storage.write(key: _keyUser, value: username);
    await _storage.write(key: _keyPass, value: password);
    // Also write fallback file for background isolate access
    await _writeFile(username, password);
  }

  /// Delete saved credentials from all stores.
  static Future<void> clear() async {
    await _storage.delete(key: _keyUser);
    await _storage.delete(key: _keyPass);
    await _deleteFile();
  }

  // ── File-based fallback for background isolates ──

  static File? _cachedFile;

  static Future<File> _getFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/credentials.json');
    return _cachedFile!;
  }

  static Future<({String username, String password})?> _loadFromFile() async {
    try {
      final file = await _getFile();
      if (!file.existsSync()) return null;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final user = data['username'] as String?;
      final pass = data['password'] as String?;
      if (user != null && pass != null && user.isNotEmpty) {
        return (username: user, password: pass);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _writeFile(String username, String password) async {
    final file = await _getFile();
    await file.writeAsString(
        jsonEncode({'username': username, 'password': password}));
  }

  static Future<void> _deleteFile() async {
    final file = await _getFile();
    if (file.existsSync()) await file.delete();
  }
}

import 'app_files.dart';

/// Simple flag to track whether first-launch onboarding has been completed.
class OnboardingStore {
  static const _marker = MarkerFile(AppFiles.onboardingComplete);

  static Future<bool> isComplete() async => (await _marker.read()) != null;

  static Future<void> markComplete() => _marker.write('done');

  /// Used by the reset flow in settings.
  static Future<void> clear() => _marker.delete();
}

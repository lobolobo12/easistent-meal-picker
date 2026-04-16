import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Simple flag to track whether first-launch onboarding has been completed.
class OnboardingStore {
  static Future<bool> isComplete() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/onboarding_complete.txt').existsSync();
  }

  static Future<void> markComplete() async {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/onboarding_complete.txt').writeAsString('done');
  }
}

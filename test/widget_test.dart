import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:easistent_meal_picker/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider — Flutter tests run without the platform plugins,
  // so any code path that hits getApplicationDocumentsDirectory()
  // (OnboardingStore, CredentialsStore, TrainingStore, ...) throws
  // MissingPluginException. Stub the channel so the app can boot to the
  // loading indicator at minimum.
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory' ||
        call.method == 'getApplicationSupportDirectory' ||
        call.method == 'getTemporaryDirectory') {
      return '/tmp/ea_test';
    }
    return null;
  });

  testWidgets('App boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MealPickerApp());

    // Initial frame shows a CircularProgressIndicator while
    // OnboardingStore.isComplete() resolves.
    expect(find.byType(MaterialApp), findsOneWidget);

    // Let the onboarding-check future settle. pumpAndSettle drives frames
    // until there are no more pending Futures/animations; it will throw
    // if something loops, so we wrap with a timeout.
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // After settle, either the onboarding flow or the main shell is up.
    // Both render at least one Scaffold.
    expect(find.byType(Scaffold), findsWidgets);
  });
}

// ignore_for_file: avoid_print, avoid_relative_lib_imports, dangling_library_doc_comments
/// End-to-end test: simulate training picks, save, reload, verify predictor changes.
import 'dart:convert';
import 'dart:io';
import '../lib/models/meal_option.dart';
import '../lib/services/meal_predictor.dart';

void main() async {
  final trainingFile = File(
      r'C:\Users\lovro\dashboards\easistent-meal-picker-app\assets\training_data.json');
  final prefsFile = File(
      r'C:\Users\lovro\dashboards\easistent-meal-picker-app\assets\preferences.json');
  final tmpFile = File(
      r'C:\Users\lovro\dashboards\easistent-meal-picker-app\build\test_training.json');

  final originalData =
      jsonDecode(await trainingFile.readAsString()) as List<dynamic>;
  final prefs =
      jsonDecode(await prefsFile.readAsString()) as Map<String, dynamic>;

  print('=== Training Flow Verification ===\n');
  print('Original training entries: ${originalData.length}');

  // 1. Build predictor from original data
  final pred1 = MealPredictor.fromData(
    trainingData: originalData,
    preferences: prefs,
  );

  // Score a test option
  const testMenu = 'Meni 6 (vegan)';
  const testDesc =
      'prosena kaša s suhim sadjem, sok';
  final score1 = pred1.scoreOption(testMenu, testDesc);
  print('Score for "$testMenu" (before training): ${score1.toStringAsFixed(4)}');

  // 2. Simulate 5 quiz picks that all choose Meni 6 (vegan) — should boost it
  final augmented = List<dynamic>.from(originalData);
  for (var i = 0; i < 5; i++) {
    augmented.add({
      'date': 'quiz-test-$i',
      'options': [
        {'menu_name': 'Meni 1', 'menu_id': 'quiz', 'description': 'lepinja, kuhan pršut, sir', 'chosen': false},
        {'menu_name': 'Meni 2', 'menu_id': 'quiz', 'description': 'bela štručka, piščančja pašteta', 'chosen': false},
        {'menu_name': 'Meni 3 (veg)', 'menu_id': 'quiz', 'description': 'polnozrnata bombeta, sir, zelenjava', 'chosen': false},
        {'menu_name': 'Meni 4 (fit)', 'menu_id': 'quiz', 'description': 'mešana solata s šunko', 'chosen': false},
        {'menu_name': 'Meni 5 (XXL +0,70€)', 'menu_id': 'quiz', 'description': 'velika lepinja, kuhan pršut, sir', 'chosen': false},
        {'menu_name': 'Meni 6 (vegan)', 'menu_id': 'quiz', 'description': testDesc, 'chosen': true},
        {'menu_name': 'Meni 7 (mesni topli)', 'menu_id': 'quiz', 'description': 'piščančji ragu, testenine', 'chosen': false},
        {'menu_name': 'Meni 8 (vegi topli)', 'menu_id': 'quiz', 'description': 'zelenjavna obara z žličniki', 'chosen': false},
      ],
    });
  }
  print('After adding 5 quiz picks: ${augmented.length} entries');

  // 3. Save to temp file (simulates TrainingStore.save)
  await tmpFile.writeAsString(jsonEncode(augmented));
  print('Saved to ${tmpFile.path}');

  // 4. Reload from disk (simulates TrainingStore.load)
  final reloaded =
      jsonDecode(await tmpFile.readAsString()) as List<dynamic>;
  print('Reloaded from disk: ${reloaded.length} entries');

  // Verify JSON round-trip preserved data types
  final lastEntry = reloaded.last as Map<String, dynamic>;
  final lastOpts = lastEntry['options'] as List;
  final chosenOpt = lastOpts.firstWhere((o) => o['chosen'] == true);
  print('Last entry date: ${lastEntry['date']}');
  print('Chosen option: ${chosenOpt['menu_name']} (chosen=${chosenOpt['chosen']}, type=${chosenOpt['chosen'].runtimeType})');

  // 5. Build predictor from reloaded data
  final pred2 = MealPredictor.fromData(
    trainingData: reloaded,
    preferences: prefs,
  );

  final score2 = pred2.scoreOption(testMenu, testDesc);
  print('\nScore for "$testMenu" (after training): ${score2.toStringAsFixed(4)}');
  print('Score delta: ${(score2 - score1).toStringAsFixed(4)}');

  if (score2 > score1) {
    print('\n[PASS] Score increased after training picks for Meni 6.');
  } else {
    print('\n[FAIL] Score did NOT increase! Something is broken.');
    exitCode = 1;
  }

  // 6. Verify the change propagates to pickBest
  // Create fake day options with Meni 6 as available
  print('\n--- pickBest comparison ---');
  final fakeDay = [
    _fakeOpt('Meni 1', 'lepinja, kuhan pršut, sir'),
    _fakeOpt('Meni 6 (vegan)', testDesc),
  ];
  final best1 = pred1.pickBest(fakeDay);
  final best2 = pred2.pickBest(fakeDay);
  print('Before training: pickBest = ${fakeDay.firstWhere((o) => o.menuId == best1).menuName}');
  print('After training:  pickBest = ${fakeDay.firstWhere((o) => o.menuId == best2).menuName}');

  // Cleanup
  if (tmpFile.existsSync()) await tmpFile.delete();
  print('\nDone.');
}

MealOption _fakeOpt(String name, String desc) => MealOption(
      menuId: name,
      menuName: name,
      description: desc,
      status: 'available',
      locationId: '0',
    );

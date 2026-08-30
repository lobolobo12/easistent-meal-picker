// Offline check that the seeded assets produce a working predictor.
// Run: dart run bin/verify_seed.dart
import 'dart:convert';
import 'dart:io';

import 'package:easistent_meal_picker/models/meal_option.dart';
import 'package:easistent_meal_picker/services/meal_predictor.dart';

void main() {
  final training =
      jsonDecode(File('assets/training_data.json').readAsStringSync())
          as List<dynamic>;
  final prefs =
      jsonDecode(File('assets/preferences.json').readAsStringSync())
          as Map<String, dynamic>;

  final predictor =
      MealPredictor.fromData(trainingData: training, preferences: prefs);

  var hits = 0, total = 0;
  for (final day in training) {
    final options = (day['options'] as List<dynamic>);
    final chosen = options.firstWhere((o) => o['chosen'] == true,
        orElse: () => null);
    if (chosen == null) continue;

    final opts = [
      for (final o in options)
        MealOption(
          menuId: o['menu_id'].toString(),
          menuName: o['menu_name'].toString(),
          description: o['description'].toString(),
          status: 'available',
          locationId: '0',
        ),
    ];
    final pick = predictor.pickBest(opts);
    total++;
    if (pick == chosen['menu_id'].toString()) hits++;
  }

  stdout.writeln('training days scored: $total');
  stdout.writeln('predictor reproduces the actual pick: $hits/$total');

  // Score spread tells us the model is discriminating, not flat.
  final sample = (training.first['options'] as List<dynamic>);
  final scores = [
    for (final o in sample)
      predictor.scoreOption(
          o['menu_name'].toString(), o['description'].toString())
  ];
  scores.sort();
  stdout.writeln('score range on one day: '
      '${scores.first.toStringAsFixed(3)} .. ${scores.last.toStringAsFixed(3)}');
}

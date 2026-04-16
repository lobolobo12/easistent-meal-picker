// ignore_for_file: avoid_print, avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';
import '../lib/services/easistent_client.dart';
import '../lib/services/meal_predictor.dart';

void main() async {
  // Load predictor data
  final trainingData = jsonDecode(
      await File(r'C:\Users\lovro\dashboards\easistent-meal-picker-app\assets\training_data.json')
          .readAsString()) as List<dynamic>;
  final prefs = jsonDecode(
      await File(r'C:\Users\lovro\dashboards\easistent-meal-picker-app\assets\preferences.json')
          .readAsString()) as Map<String, dynamic>;

  final predictor = MealPredictor.fromData(
    trainingData: trainingData,
    preferences: prefs,
  );
  print('Predictor built: ${trainingData.length} training days\n');

  // Login and fetch menu
  final config = jsonDecode(
      await File(r'C:\Users\lovro\easistent-meal-picker\config.json')
          .readAsString());
  final client =
      EAsistentClient(username: config['username'], password: config['password']);

  print('Logging in...');
  await client.login();

  final html = await client.getMealPage();
  final week = client.findCurrentWeek(html);
  final menu = client.parseMealTable(html);
  print('Week $week — ${menu.length} days\n');

  for (final date in menu.keys.toList()..sort()) {
    final options = menu[date]!;
    final scores = predictor.scoreDay(options);
    final bestId = predictor.pickBest(options);

    print('--- $date ---');
    // Sort by score descending
    final sorted = options.toList()
      ..sort((a, b) => (scores[b.menuId] ?? 0).compareTo(scores[a.menuId] ?? 0));

    for (final opt in sorted) {
      final s = scores[opt.menuId] ?? 0.0;
      final marker = opt.menuId == bestId ? ' >> ' : '    ';
      final status = opt.status.padRight(9);
      final desc = opt.description.length > 50
          ? '${opt.description.substring(0, 50)}...'
          : opt.description;
      print('$marker[$status] ${opt.menuName.padRight(22)} '
          '${s >= 0 ? "+" : ""}${s.toStringAsFixed(3).padLeft(6)}  $desc');
    }
    print('');
  }
}

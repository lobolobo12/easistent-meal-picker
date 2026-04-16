import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../models/meal_option.dart';
import 'easistent_client.dart';
import 'meal_predictor.dart';

const _androidWidgetName = 'MealWidgetProvider';
const _androidWidgetQualified =
    'com.easistent.mealpicker.MealWidgetProvider';

/// Update the Android home-screen widget with today's and tomorrow's meal.
///
/// [menu] is the current week's parsed meal map (date → options).
/// [predictor] is used to pick the best option for days without an order.
/// [selections] maps date → selected menuId (user or AI pick).
Future<void> updateHomeWidget({
  required Map<String, List<MealOption>> menu,
  MealPredictor? predictor,
  Map<String, String> selections = const {},
}) async {
  final now = DateTime.now();
  final todayStr = _fmtDate(now);
  final tomorrowStr = _fmtDate(now.add(const Duration(days: 1)));

  final todayResult = _resolveMeal(menu, todayStr, selections, predictor);
  final tomorrowResult =
      _resolveMeal(menu, tomorrowStr, selections, predictor);

  await HomeWidget.saveWidgetData<String>(
      'today_menu', todayResult.$1);
  await HomeWidget.saveWidgetData<String>(
      'today_desc', todayResult.$2);
  await HomeWidget.saveWidgetData<String>(
      'tomorrow_menu', tomorrowResult.$1);
  await HomeWidget.saveWidgetData<String>(
      'tomorrow_desc', tomorrowResult.$2);
  await HomeWidget.saveWidgetData<String>(
      'last_updated', now.toIso8601String());

  await HomeWidget.updateWidget(
    qualifiedAndroidName: _androidWidgetQualified,
    androidName: _androidWidgetName,
  );
}

/// Resolve the meal name + description for a given date.
(String, String) _resolveMeal(
  Map<String, List<MealOption>> menu,
  String date,
  Map<String, String> selections,
  MealPredictor? predictor,
) {
  final opts = menu[date];
  if (opts == null || opts.isEmpty) return ('', '');

  // 1. Explicit selection
  final selId = selections[date];
  if (selId != null) {
    final opt = opts.where((o) => o.menuId == selId).firstOrNull;
    if (opt != null) return (opt.menuName, _cleanDesc(opt.description));
  }

  // 2. Currently ordered
  final ordered = opts.where((o) => o.status == 'ordered').firstOrNull;
  if (ordered != null) {
    return (ordered.menuName, _cleanDesc(ordered.description));
  }

  // 3. AI pick
  if (predictor != null) {
    final bestId = predictor.pickBest(opts);
    if (bestId != null) {
      final best = opts.firstWhere((o) => o.menuId == bestId);
      return (best.menuName, _cleanDesc(best.description));
    }
  }

  return ('', '');
}

/// Update widget from background (e.g. after auto-submit).
/// Reads credentials, training data, preferences from disk, logs in,
/// fetches menu, and updates the widget.
Future<void> updateHomeWidgetBackground() async {
  try {
    final dir = await getApplicationDocumentsDirectory();

    final credsFile = File('${dir.path}/credentials.json');
    if (!credsFile.existsSync()) return;
    final credsData =
        jsonDecode(await credsFile.readAsString()) as Map<String, dynamic>;
    final username = credsData['username'] as String?;
    final password = credsData['password'] as String?;
    if (username == null || password == null) return;

    final trainingFile = File('${dir.path}/training_data.json');
    final prefsFile = File('${dir.path}/preferences.json');
    final ratingsFile = File('${dir.path}/meal_ratings.json');

    List<dynamic> trainingData = [];
    Map<String, dynamic> preferences = {};
    List<dynamic> ratings = [];

    if (trainingFile.existsSync()) {
      trainingData =
          jsonDecode(await trainingFile.readAsString()) as List<dynamic>;
    }
    if (prefsFile.existsSync()) {
      preferences =
          jsonDecode(await prefsFile.readAsString()) as Map<String, dynamic>;
    }
    if (ratingsFile.existsSync()) {
      try {
        ratings =
            jsonDecode(await ratingsFile.readAsString()) as List<dynamic>;
      } catch (_) {}
    }

    final predictor = MealPredictor.fromData(
      trainingData: trainingData,
      preferences: preferences,
      ratings: ratings,
    );

    final client = EAsistentClient(username: username, password: password);
    await client.login();
    final html = await client.getMealPage();
    final menu = client.parseMealTable(html);

    await updateHomeWidget(menu: menu, predictor: predictor);
  } catch (_) {
    // Non-fatal — widget just won't update
  }
}

/// Strip allergen parentheticals from a meal description.
String _cleanDesc(String desc) {
  return desc
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .trim()
      .replaceAll(RegExp(r',\s*$'), '');
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

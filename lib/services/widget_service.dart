import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../models/meal_option.dart';
import '../util/dates.dart';
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
  // The widget is an Android AppWidget provider; there is no iOS WidgetKit
  // extension in this project, so saving data would go nowhere and
  // updateWidget would fail on a missing app group.
  if (!Platform.isAndroid) return;

  final now = DateTime.now();
  final todayStr = fmtYmd(now);
  final tomorrowStr = fmtYmd(now.add(const Duration(days: 1)));

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

/// Strip allergen parentheticals from a meal description.
String _cleanDesc(String desc) {
  return desc
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .trim()
      .replaceAll(RegExp(r',\s*$'), '');
}


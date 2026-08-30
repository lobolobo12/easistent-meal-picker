// Walk-forward evaluation of the predictor against the recorded training data.
//
// For each day i, a model is built from days [0, i) only and asked to pick
// day i. That is the honest question — "would it have chosen what I chose,
// given only what it knew at the time" — as opposed to scoring the days it
// was trained on, which is trivially near-perfect and tells you nothing.
//
//   dart run bin/eval_predictor.dart [path/to/training_data.json]
//
// Defaults to assets/training_data.json.

import 'dart:convert';
import 'dart:io';

import 'package:easistent_meal_picker/services/meal_predictor.dart';
import 'package:easistent_meal_picker/services/preference_learner.dart';

void main(List<String> args) {
  final path =
      args.isNotEmpty ? args.first : 'assets/training_data.json';
  final prefsPath = 'assets/preferences.json';

  final data = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  final prefs = File(prefsPath).existsSync()
      ? jsonDecode(File(prefsPath).readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};

  data.sort((a, b) =>
      ((a as Map)['date'] as String).compareTo((b as Map)['date'] as String));

  stdout.writeln('Days: ${data.length}  '
      'Options/day: ${(data.first as Map)['options'].length}');
  stdout.writeln('');

  final variants = <String, PredictorTuning>{
    'freq>=3, no shrinkage (legacy)': PredictorTuning.legacy,
    'freq>=2, no shrinkage':
        const PredictorTuning(minTokenFreq: 2, shrinkageK: 0),
    'freq>=1, no shrinkage':
        const PredictorTuning(minTokenFreq: 1, shrinkageK: 0),
    'freq>=1, shrinkage k=1':
        const PredictorTuning(minTokenFreq: 1, shrinkageK: 1),
    'freq>=1, shrinkage k=2':
        const PredictorTuning(minTokenFreq: 1, shrinkageK: 2),
    'freq>=1, shrinkage k=4':
        const PredictorTuning(minTokenFreq: 1, shrinkageK: 4),
    'freq>=1, shrinkage k=8':
        const PredictorTuning(minTokenFreq: 1, shrinkageK: 8),
    'shipped default': PredictorTuning.current,
    'shipped, but keyword unscaled':
        const PredictorTuning(keywordEvidenceK: 0),
  };

  for (final entry in variants.entries) {
    final r = _walkForward(data, prefs, entry.value);
    final name = entry.key.padRight(34);
    final top1 = 'top-1 ${r.correct}/${r.scored}'.padRight(14);
    final rank = r.meanRank.toStringAsFixed(2);
    stdout.writeln('$name${top1}mean rank $rank   vocab ${r.vocab}');
  }

  stdout.writeln('');
  stdout.writeln('Baselines — the model must beat these to be worth having:');
  final mode = _modeBaseline(data);
  final modeLabel = '  "most-picked menu so far"'.padRight(34);
  stdout.writeln('${modeLabel}top-1 ${mode.correct}/${mode.scored}');
  final randLabel = '  uniform random over 8 options'.padRight(34);
  final randHits = (data.length / 8).toStringAsFixed(1);
  stdout.writeln('${randLabel}top-1 $randHits/${data.length}');
}

/// Predict whichever menu has been chosen most often so far.
///
/// This exists because the model was once measurably worse than it: the
/// keyword signal carried the largest weight while being built from a
/// handful of days, and it overrode a menu preference the user held 86% of
/// the time. Any change to the scoring has to be checked against this.
_Result _modeBaseline(List<dynamic> data) {
  var correct = 0, scored = 0;
  for (var i = 1; i < data.length; i++) {
    final counts = <String, int>{};
    for (final d in data.sublist(0, i)) {
      for (final o in ((d as Map)['options'] as List).cast<Map>()) {
        if (o['chosen'] == true) {
          final k = normalizeMenuName(o['menu_name'] as String);
          counts[k] = (counts[k] ?? 0) + 1;
        }
      }
    }
    if (counts.isEmpty) continue;
    final mode =
        counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;

    final options = ((data[i] as Map)['options'] as List).cast<Map>();
    final actual = options.firstWhere((o) => o['chosen'] == true,
        orElse: () => const {});
    if (actual.isEmpty) continue;
    scored++;
    if (normalizeMenuName(actual['menu_name'] as String) == mode) correct++;
  }
  return _Result(correct, scored, 0, 0);
}

class _Result {
  final int correct;
  final int scored;
  final double meanRank;
  final int vocab;
  _Result(this.correct, this.scored, this.meanRank, this.vocab);
}

_Result _walkForward(
    List<dynamic> data, Map<String, dynamic> prefs, PredictorTuning tuning) {
  var correct = 0;
  var scored = 0;
  var rankSum = 0;
  var vocab = 0;

  for (var i = 1; i < data.length; i++) {
    final train = data.sublist(0, i);

    // Re-derive the auto preferences from the training slice only. The
    // stored preferences.json was learned from every day including this
    // one, so feeding it in leaks the label and scores a flat 6/6 — which
    // is exactly what the first version of this harness reported.
    final foldPrefs = deriveAutoPreferences(
      trainingData: train,
      currentPrefs: {
        'liked_keywords': prefs['liked_keywords'] ?? [],
        'disliked_keywords': prefs['disliked_keywords'] ?? [],
      },
    );

    final model = MealPredictor.fromData(
      trainingData: train,
      preferences: foldPrefs,
      tuning: tuning,
    );
    if (i == data.length - 1) vocab = model.vocabularySize;

    final day = data[i] as Map;
    final options = (day['options'] as List).cast<Map>();
    final actual = options.firstWhere((o) => o['chosen'] == true,
        orElse: () => const {});
    if (actual.isEmpty) continue;

    // Rank every option by score; where did the real choice land?
    final ranked = options
        .map((o) => (
              id: o['menu_id'] as String,
              score: model.scoreOption(
                  o['menu_name'] as String, o['description'] as String),
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final rank =
        ranked.indexWhere((e) => e.id == actual['menu_id'] as String) + 1;
    if (rank == 1) correct++;
    rankSum += rank;
    scored++;
  }

  return _Result(
      correct, scored, scored == 0 ? 0 : rankSum / scored, vocab);
}

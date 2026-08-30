/// Shaping rules for the training data file.
///
/// Deliberately free of Flutter imports: `bin/eval_predictor.dart` runs under
/// plain `dart run` and has to apply exactly the same collapsing the app
/// does, or it would score a file of triplicated rows as three times as many
/// days — with each day's own copies leaking into the folds meant to predict
/// it.
library;

import 'dart:convert';

/// Fold identical training days into a single entry carrying a `weight`.
///
/// Submitting a week used to append the same day three times to give it extra
/// pull. That inflated the raw token counts as well as the rates, so a
/// manually submitted day slipped past the model's frequency floor while a
/// scraped day of identical content did not — the model behaved differently
/// depending on where the data came from. A weight says the same thing
/// without lying about how much has actually been seen.
///
/// Idempotent: already-collapsed data passes through unchanged.
List<dynamic> collapseTrainingDuplicates(List<dynamic> data) {
  final order = <String>[];
  final byKey = <String, Map<String, dynamic>>{};
  final weights = <String, double>{};

  for (final entry in data) {
    if (entry is! Map) continue;
    final copy = Map<String, dynamic>.from(entry);
    final weight = (copy.remove('weight') as num?)?.toDouble() ?? 1.0;
    final key = jsonEncode(copy);
    if (!byKey.containsKey(key)) {
      order.add(key);
      byKey[key] = copy;
      weights[key] = 0;
    }
    weights[key] = weights[key]! + weight;
  }

  return [
    for (final key in order)
      {
        ...byKey[key]!,
        // Keep the file readable: only say weight when it is not 1.
        if (weights[key]! != 1.0) 'weight': _tidy(weights[key]!),
      }
  ];
}

num _tidy(double w) => w == w.roundToDouble() ? w.round() : w;

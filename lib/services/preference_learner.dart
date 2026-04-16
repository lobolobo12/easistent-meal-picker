import 'meal_predictor.dart' show tokenize, normalizeMenuName;

const _minFreq = 5;
const _likeThreshold = 0.25;
const _dislikeThreshold = -0.25;
const _maxAutoKeywords = 20;

/// Analyze training data and return updated preferences with auto-derived
/// liked/disliked keywords and recalculated menu type ranking.
///
/// Preserves all manual keywords. Auto keywords are stored separately so the
/// settings screen can distinguish them visually.
Map<String, dynamic> deriveAutoPreferences({
  required List<dynamic> trainingData,
  required Map<String, dynamic> currentPrefs,
}) {
  final manualLiked = _stringList(currentPrefs['liked_keywords']);
  final manualDisliked = _stringList(currentPrefs['disliked_keywords']);
  final manualSet = {...manualLiked, ...manualDisliked};

  // ── Keyword analysis (same base-rate correction as predictor) ──

  final chosenCounts = <String, int>{};
  final rejectedCounts = <String, int>{};
  var totalOptions = 0;
  var totalChosen = 0;

  for (final day in trainingData) {
    for (final opt in (day as Map)['options'] as List) {
      final tokens = tokenize((opt as Map)['description'] as String);
      final chosen = opt['chosen'] as bool;
      for (final t in tokens) {
        if (chosen) {
          chosenCounts[t] = (chosenCounts[t] ?? 0) + 1;
        } else {
          rejectedCounts[t] = (rejectedCounts[t] ?? 0) + 1;
        }
      }
      if (chosen) totalChosen++;
      totalOptions++;
    }
  }

  final baseline = totalOptions > 0 ? totalChosen / totalOptions : 0.125;

  final autoLiked = <String>[];
  final autoDisliked = <String>[];

  final allTokens = {...chosenCounts.keys, ...rejectedCounts.keys};
  // Compute scores, collect candidates
  final candidates = <String, double>{};
  for (final token in allTokens) {
    final c = chosenCounts[token] ?? 0;
    final r = rejectedCounts[token] ?? 0;
    if (c + r < _minFreq) continue;
    if (manualSet.contains(token)) continue; // already manual

    final rate = c / (c + r);
    final score = rate >= baseline
        ? (rate - baseline) / (1 - baseline)
        : (rate - baseline) / baseline;
    candidates[token] = score;
  }

  // Sort by score descending for liked, ascending for disliked
  final sortedByScore = candidates.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  for (final e in sortedByScore) {
    if (e.value > _likeThreshold && autoLiked.length < _maxAutoKeywords) {
      autoLiked.add(e.key);
    }
  }
  for (final e in sortedByScore.reversed) {
    if (e.value < _dislikeThreshold &&
        autoDisliked.length < _maxAutoKeywords) {
      autoDisliked.add(e.key);
    }
  }

  // ── Menu type ranking by pick frequency ──

  final typeChosen = <String, int>{};
  final typeTotal = <String, int>{};

  for (final day in trainingData) {
    for (final opt in (day as Map)['options'] as List) {
      final name = normalizeMenuName((opt as Map)['menu_name'] as String);
      typeTotal[name] = (typeTotal[name] ?? 0) + 1;
      if (opt['chosen'] as bool) {
        typeChosen[name] = (typeChosen[name] ?? 0) + 1;
      }
    }
  }

  final rankedTypes = typeTotal.keys.toList()
    ..sort((a, b) {
      final rateA = (typeChosen[a] ?? 0) / typeTotal[a]!;
      final rateB = (typeChosen[b] ?? 0) / typeTotal[b]!;
      return rateB.compareTo(rateA);
    });

  // ── Build updated preferences ──

  return {
    'liked_keywords': manualLiked,
    'disliked_keywords': manualDisliked,
    'auto_liked_keywords': autoLiked,
    'auto_disliked_keywords': autoDisliked,
    'menu_type_ranking': rankedTypes,
  };
}

List<String> _stringList(dynamic value) =>
    (value as List<dynamic>? ?? []).map((e) => e.toString()).toList();

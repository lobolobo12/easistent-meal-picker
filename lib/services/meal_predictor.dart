import '../models/meal_option.dart';

const _stopWords = {
  'v', 'z', 's', 'in', 'ki', 'iz', 'na', 'za', 'od', 'po', 'se', 'je',
  'da', 'sok', 'vsebuje', 'izdelek', 'sledi', 'laktozo',
};
const _minTokenLen = 3;
const _minTokenFreq = 3;

// Weights for the scoring signals
const _wKeyword = 1.0;
const _wMenuType = 0.3;
const _wManual = 0.4;
const _wRating = 0.5;

// ── Odjava (cancel) fallback threshold ──
//
// When every available option on a day scores at or below this value AND
// no option is positive, the predictor recommends Odjava instead of the
// "least-bad" meal. Tune this to taste — more negative means Odjava is
// recommended less often; closer to 0 means it fires more readily.
const kOdjavaScoreThreshold = -0.3;

/// Tokenize a Slovenian food description into lowercase word tokens.
List<String> tokenize(String description) {
  var text = description.toLowerCase();
  // Strip allergen parentheticals: (pšenica, mlečni izdelek, ...)
  text = text.replaceAll(RegExp(r'\([^)]*\)'), '');
  return [
    for (final m in RegExp(r'[a-zčšžćđ]+').allMatches(text))
      if (m.group(0)!.length >= _minTokenLen &&
          !_stopWords.contains(m.group(0)!))
        m.group(0)!
  ];
}

String normalizeMenuName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Hybrid meal predictor using keyword scoring, menu type frequency,
/// and manual preference overrides with base-rate correction.
class MealPredictor {
  final Map<String, double> _keywordScores;
  final Map<String, double> _menuTypeScores;
  final List<String> _likedKeywords;
  final List<String> _dislikedKeywords;
  final Map<String, double> _manualMenuScores;
  final Map<String, double> _ratingKeywordScores;

  MealPredictor._({
    required Map<String, double> keywordScores,
    required Map<String, double> menuTypeScores,
    required List<String> likedKeywords,
    required List<String> dislikedKeywords,
    required Map<String, double> manualMenuScores,
    required Map<String, double> ratingKeywordScores,
  })  : _keywordScores = keywordScores,
        _menuTypeScores = menuTypeScores,
        _likedKeywords = likedKeywords,
        _dislikedKeywords = dislikedKeywords,
        _manualMenuScores = manualMenuScores,
        _ratingKeywordScores = ratingKeywordScores;

  /// Build predictor from training data, user preferences, and optional ratings.
  factory MealPredictor.fromData({
    required List<dynamic> trainingData,
    required Map<String, dynamic> preferences,
    List<dynamic>? ratings,
  }) {
    final keywordScores = _buildKeywordModel(trainingData);
    final menuTypeScores = _buildMenuTypeModel(trainingData);
    final ratingKeywordScores = _buildRatingModel(ratings ?? []);

    final liked = [
      ...(preferences['liked_keywords'] as List<dynamic>? ?? [])
          .map((k) => k.toString().toLowerCase()),
      ...(preferences['auto_liked_keywords'] as List<dynamic>? ?? [])
          .map((k) => k.toString().toLowerCase()),
    ];
    final disliked = [
      ...(preferences['disliked_keywords'] as List<dynamic>? ?? [])
          .map((k) => k.toString().toLowerCase()),
      ...(preferences['auto_disliked_keywords'] as List<dynamic>? ?? [])
          .map((k) => k.toString().toLowerCase()),
    ];

    final ranking = (preferences['menu_type_ranking'] as List<dynamic>? ?? [])
        .map((k) => k.toString())
        .toList();
    final manualMenuScores = <String, double>{};
    for (var i = 0; i < ranking.length; i++) {
      final denom = (ranking.length - 1).clamp(1, ranking.length).toDouble();
      manualMenuScores[normalizeMenuName(ranking[i])] = 1.0 - i / denom;
    }

    return MealPredictor._(
      keywordScores: keywordScores,
      menuTypeScores: menuTypeScores,
      likedKeywords: liked,
      dislikedKeywords: disliked,
      manualMenuScores: manualMenuScores,
      ratingKeywordScores: ratingKeywordScores,
    );
  }

  /// Learn per-token preference scores from labeled training data.
  /// Uses base-rate correction: with ~8 options/day, random pick rate is
  /// ~12.5%, so that is the neutral point (score 0), not 50%.
  static Map<String, double> _buildKeywordModel(List<dynamic> data) {
    final chosenCounts = <String, int>{};
    final rejectedCounts = <String, int>{};
    var totalOptions = 0;
    var totalChosen = 0;

    for (final day in data) {
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
    final scores = <String, double>{};

    for (final token in {...chosenCounts.keys, ...rejectedCounts.keys}) {
      final c = chosenCounts[token] ?? 0;
      final r = rejectedCounts[token] ?? 0;
      if (c + r < _minTokenFreq) continue;
      final rate = c / (c + r);
      scores[token] = rate >= baseline
          ? (rate - baseline) / (1 - baseline)
          : (rate - baseline) / baseline;
    }

    return scores;
  }

  /// Learn menu type preference from historical pick frequency.
  static Map<String, double> _buildMenuTypeModel(List<dynamic> data) {
    final typeChosen = <String, int>{};
    final typeTotal = <String, int>{};

    for (final day in data) {
      for (final opt in (day as Map)['options'] as List) {
        final name = normalizeMenuName((opt as Map)['menu_name'] as String);
        typeTotal[name] = (typeTotal[name] ?? 0) + 1;
        if (opt['chosen'] as bool) {
          typeChosen[name] = (typeChosen[name] ?? 0) + 1;
        }
      }
    }

    return {
      for (final name in typeTotal.keys)
        name: (typeChosen[name] ?? 0) / typeTotal[name]!,
    };
  }

  /// Build per-token scores from meal ratings (1-5 stars).
  ///
  /// Ratings are normalized to [-1, +1]: rating 3 = 0 (neutral),
  /// rating 5 = +1 (loved), rating 1 = -1 (hated). Each token in the
  /// rated meal's description accumulates the weighted average.
  static Map<String, double> _buildRatingModel(List<dynamic> ratings) {
    final tokenSums = <String, double>{};
    final tokenCounts = <String, int>{};

    for (final r in ratings) {
      if (r is! Map<String, dynamic>) continue;
      final desc = r['description'] as String? ?? '';
      final rating = r['rating'] as int? ?? 3;
      // Normalize: 1→-1, 2→-0.5, 3→0, 4→+0.5, 5→+1
      final normalized = (rating - 3) / 2.0;
      final tokens = tokenize(desc);
      for (final t in tokens) {
        tokenSums[t] = (tokenSums[t] ?? 0) + normalized;
        tokenCounts[t] = (tokenCounts[t] ?? 0) + 1;
      }
    }

    return {
      for (final t in tokenSums.keys)
        if (tokenCounts[t]! >= 1) t: tokenSums[t]! / tokenCounts[t]!,
    };
  }

  /// Score a single menu option. Higher = more preferred.
  double scoreOption(String menuName, String description) {
    final tokens = tokenize(description);
    final descLower = description.toLowerCase();
    final normName = normalizeMenuName(menuName);

    // 1. Keyword score: average of known token scores
    final known = [
      for (final t in tokens)
        if (_keywordScores.containsKey(t)) _keywordScores[t]!
    ];
    final keywordScore =
        known.isNotEmpty ? known.reduce((a, b) => a + b) / known.length : 0.0;

    // 2. Menu type score: historical pick rate
    var menuScore = _menuTypeScores[normName] ?? 0.0;

    // 3. Manual keyword overrides
    var manualScore = 0.0;
    for (final kw in _likedKeywords) {
      if (descLower.contains(kw)) manualScore += 1.0;
    }
    for (final kw in _dislikedKeywords) {
      if (descLower.contains(kw)) manualScore -= 1.0;
    }

    // Blend menu type with manual ranking (70/30 learned vs manual)
    if (_manualMenuScores.isNotEmpty) {
      final manualMenu = _manualMenuScores[normName] ?? 0.0;
      menuScore = 0.7 * menuScore + 0.3 * manualMenu;
    }

    // 4. Rating-based keyword score: average of known rating token scores
    var ratingScore = 0.0;
    if (_ratingKeywordScores.isNotEmpty) {
      final ratingKnown = [
        for (final t in tokens)
          if (_ratingKeywordScores.containsKey(t)) _ratingKeywordScores[t]!
      ];
      if (ratingKnown.isNotEmpty) {
        ratingScore =
            ratingKnown.reduce((a, b) => a + b) / ratingKnown.length;
      }
    }

    return _wKeyword * keywordScore +
        _wMenuType * menuScore +
        _wManual * manualScore +
        _wRating * ratingScore;
  }

  /// Score all options for a day. Returns menuId → score.
  Map<String, double> scoreDay(List<MealOption> options) => {
        for (final opt in options)
          opt.menuId: scoreOption(opt.menuName, opt.description),
      };

  /// Pick the best available option for a day. Returns menuId or null.
  String? pickBest(List<MealOption> options) {
    String? bestId;
    var bestScore = double.negativeInfinity;

    for (final opt in options) {
      if (opt.status != 'available') continue;
      final score = scoreOption(opt.menuName, opt.description);
      if (score > bestScore) {
        bestScore = score;
        bestId = opt.menuId;
      }
    }

    return bestId;
  }

  /// Pick the best option, or recommend Odjava when every available option
  /// is strongly negative.
  ///
  /// Odjava is recommended when:
  ///   - at least one option was scored (so we're not on an unseen menu), AND
  ///   - no option has a positive score, AND
  ///   - the best (maximum) score is at or below [kOdjavaScoreThreshold].
  ///
  /// When any of those conditions fail, falls back to [pickBest] behavior.
  PickResult pickBestOrOdjava(List<MealOption> options) {
    String? bestId;
    var bestScore = double.negativeInfinity;

    for (final opt in options) {
      if (opt.status != 'available') continue;
      final score = scoreOption(opt.menuName, opt.description);
      if (score > bestScore) {
        bestScore = score;
        bestId = opt.menuId;
      }
    }

    if (bestId == null) return const PickResult.none();

    // All-negative check: the best score is not positive. Combined with the
    // threshold check, this avoids triggering Odjava when scores are only
    // mildly negative (e.g. a cold baseline with no strong signal).
    if (bestScore <= 0 && bestScore <= kOdjavaScoreThreshold) {
      return PickResult.odjava(bestScore: bestScore);
    }

    return PickResult.menu(bestId, score: bestScore);
  }
}

/// Outcome of [MealPredictor.pickBestOrOdjava].
class PickResult {
  /// Picked menu id, null when [recommendOdjava] or when no option was
  /// scoreable.
  final String? menuId;

  /// True when every available option scored strongly negative and the
  /// caller should submit Odjava instead of any menu.
  final bool recommendOdjava;

  /// Highest raw score observed (even when Odjava is recommended).
  final double? bestScore;

  const PickResult._({
    this.menuId,
    this.recommendOdjava = false,
    this.bestScore,
  });

  const PickResult.none() : this._();
  const PickResult.menu(String id, {required double score})
      : this._(menuId: id, bestScore: score);
  const PickResult.odjava({required double bestScore})
      : this._(recommendOdjava: true, bestScore: bestScore);
}

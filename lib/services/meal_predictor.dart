import '../models/meal_option.dart';

const _stopWords = {
  'v', 'z', 's', 'in', 'ki', 'iz', 'na', 'za', 'od', 'po', 'se', 'je',
  'da', 'sok', 'vsebuje', 'izdelek', 'sledi', 'laktozo',
};
const _minTokenLen = 3;

/// Tunable knobs for the scoring model.
///
/// These used to be bare top-level constants, which made it impossible to
/// score the same data under two settings and compare — so any change to the
/// model was a guess. `bin/eval_predictor.dart` now walks the training data
/// forward under both [legacy] and [current] and reports the difference.
class PredictorTuning {
  /// Weights for the four scoring signals.
  final double wKeyword;
  final double wMenuType;
  final double wManual;
  final double wRating;

  /// Tokens seen fewer than this many times are dropped outright.
  final int minTokenFreq;

  /// Confidence shrinkage for the keyword model: a token's score is scaled by
  /// `n / (n + k)`, where n is how often it was seen.
  ///
  /// The old model had a hard cutoff at three occurrences and nothing else, so
  /// a token seen twice counted for nothing and a token seen three times
  /// counted in full. On a dataset this small that discarded most of the
  /// vocabulary. Shrinkage keeps rare tokens but trusts them less, which is
  /// what their evidence actually supports. 0 disables it.
  final double shrinkageK;

  /// How many distinct training days it takes for the keyword signal to
  /// carry half of [wKeyword].
  ///
  /// The keyword score is the noisiest signal in the model and it carried the
  /// largest weight, which is backwards when it is built from a handful of
  /// days. Scaling it by `days / (days + k)` lets the menu preference lead
  /// early and hands influence to the keywords as they earn it. 0 disables
  /// the scaling.
  final double keywordEvidenceK;

  /// Same idea for the ratings model, which had no floor at all.
  ///
  /// This one is kept on, on a structural argument rather than a measured
  /// one — there are no ratings in the training data to evaluate against.
  /// A single 5-star rating gave *every* word in that description the full
  /// +1 at [wRating], so rating one bread roll highly promoted every meal
  /// containing the word "kruh" thereafter. Scaling by n/(n+2) leaves a
  /// first rating a third of its former pull and restores it as evidence
  /// accumulates; it can only ever damp the weakest evidence.
  final double ratingShrinkageK;

  const PredictorTuning({
    this.wKeyword = 1.0,
    this.wMenuType = 1.0,
    this.wManual = 0.4,
    this.wRating = 0.5,
    this.minTokenFreq = 3,
    this.shrinkageK = 0,
    this.ratingShrinkageK = 2.0,
    this.keywordEvidenceK = 30.0,
  });

  /// The keyword model exactly as it behaved before, for comparison in
  /// `bin/eval_predictor.dart`.
  ///
  /// Shrinkage looked like an obvious win for a dataset this small — it
  /// raises the vocabulary from 25 tokens to 118 — but walk-forward
  /// evaluation could not confirm it. Across k = 1, 2, 4, 8 the top-1 score
  /// went 2/6, 2/6, 4/6, 3/6: non-monotonic, swinging by two days out of six.
  /// That is noise, and choosing the best cell of that table would be fitting
  /// the validation set. So the shipped keyword model is unchanged, and this
  /// stays here to re-run the comparison once a real season of data exists.
  static const legacy = PredictorTuning(
    wMenuType: 0.3,
    ratingShrinkageK: 0,
    keywordEvidenceK: 0,
  );

  /// What the app ships.
  static const current = PredictorTuning();
}

// ── Odjava (cancel) fallback threshold ──
//
// When every available option on a day scores at or below this value AND
// no option is positive, the predictor recommends Odjava instead of the
// "least-bad" meal. Tune this to taste — more negative means Odjava is
// recommended less often; closer to 0 means it fires more readily.
const kOdjavaScoreThreshold = -0.3;

/// Weight given to a day where the user overrode the model's pick.
///
/// Unmeasured: the training data does not record whether a past day was a
/// correction, so there is no history to evaluate this against. It rests on
/// the argument that a deliberate override is stronger evidence than an
/// accepted default, and it is deliberately modest so that being wrong about
/// that costs little.
const kCorrectionWeight = 3;

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

/// Canonical identity for a menu, used as a model key — never for display.
///
/// The descriptive suffix changes between years: this school renamed
/// "Meni 5 (XXL +0,70€)" to "Meni 5 (XXL+0,80 EUR)" over the summer. Keying
/// on the full string would strand every preference learned about that menu
/// under a name the site no longer serves, and would show it twice wherever
/// the two are pooled together. Identity is the part before the bracket.
String normalizeMenuName(String name) {
  final base = name.split('(').first.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (base.isNotEmpty) return base;
  return name.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Hybrid meal predictor using keyword scoring, menu type frequency,
/// and manual preference overrides with base-rate correction.
class MealPredictor {
  final Map<String, double> _keywordScores;
  final Map<String, double> _menuTypeScores;
  final List<String> _likedKeywords;
  final List<String> _dislikedKeywords;
  final Map<String, double> _manualMenuScores;
  final Map<String, double> _ratingKeywordScores;
  final PredictorTuning _tuning;

  /// [PredictorTuning.wKeyword] after evidence scaling — see
  /// [PredictorTuning.keywordEvidenceK].
  final double _effectiveWKeyword;

  MealPredictor._({
    required Map<String, double> keywordScores,
    required Map<String, double> menuTypeScores,
    required List<String> likedKeywords,
    required List<String> dislikedKeywords,
    required Map<String, double> manualMenuScores,
    required Map<String, double> ratingKeywordScores,
    required PredictorTuning tuning,
    required double effectiveWKeyword,
  })  : _keywordScores = keywordScores,
        _menuTypeScores = menuTypeScores,
        _likedKeywords = likedKeywords,
        _dislikedKeywords = dislikedKeywords,
        _manualMenuScores = manualMenuScores,
        _ratingKeywordScores = ratingKeywordScores,
        _tuning = tuning,
        _effectiveWKeyword = effectiveWKeyword;

  /// Build predictor from training data, user preferences, and optional ratings.
  factory MealPredictor.fromData({
    required List<dynamic> trainingData,
    required Map<String, dynamic> preferences,
    List<dynamic>? ratings,
    PredictorTuning tuning = PredictorTuning.current,
  }) {
    // Distinct dates, not entry count: a manually submitted day is written
    // to the training file three times for extra weight, so counting rows
    // would make the model's confidence depend on where the data came from.
    final trainingDays = <String>{
      for (final day in trainingData)
        if (day is Map && day['date'] is String) day['date'] as String,
    }.length;
    final effectiveWKeyword = tuning.keywordEvidenceK <= 0
        ? tuning.wKeyword
        : tuning.wKeyword *
            (trainingDays / (trainingDays + tuning.keywordEvidenceK));

    final keywordScores = _buildKeywordModel(trainingData, tuning);
    final menuTypeScores = _buildMenuTypeModel(trainingData);
    final ratingKeywordScores = _buildRatingModel(ratings ?? [], tuning);

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
      tuning: tuning,
      effectiveWKeyword: effectiveWKeyword,
    );
  }

  /// A training day's weight — how much this one day should count.
  ///
  /// A day the user actively corrected the model on says more than one they
  /// waved through, so entries carry a weight rather than being written to
  /// the file several times over. Duplicating rows, which is what this code
  /// used to do, inflated the raw counts as well as the rates, which quietly
  /// let weighted days slip past [PredictorTuning.minTokenFreq] while
  /// scraped ones could not.
  static double _weightOf(Map day) {
    final w = day['weight'];
    if (w is num && w > 0) return w.toDouble();
    return 1.0;
  }

  /// Learn per-token preference scores from labeled training data.
  /// Uses base-rate correction: with ~8 options/day, random pick rate is
  /// ~12.5%, so that is the neutral point (score 0), not 50%.
  static Map<String, double> _buildKeywordModel(
      List<dynamic> data, PredictorTuning tuning) {
    final chosenWeight = <String, double>{};
    final rejectedWeight = <String, double>{};
    // Unweighted sightings, kept separately so the frequency floor asks
    // "how often have I actually seen this word" rather than "how much do
    // the days it appeared on count for".
    final sightings = <String, int>{};
    var totalOptions = 0.0;
    var totalChosen = 0.0;

    for (final day in data) {
      final weight = _weightOf(day as Map);
      for (final opt in day['options'] as List) {
        final tokens = tokenize((opt as Map)['description'] as String);
        final chosen = opt['chosen'] as bool;
        for (final t in tokens) {
          sightings[t] = (sightings[t] ?? 0) + 1;
          if (chosen) {
            chosenWeight[t] = (chosenWeight[t] ?? 0) + weight;
          } else {
            rejectedWeight[t] = (rejectedWeight[t] ?? 0) + weight;
          }
        }
        if (chosen) totalChosen += weight;
        totalOptions += weight;
      }
    }

    final baseline = totalOptions > 0 ? totalChosen / totalOptions : 0.125;
    final scores = <String, double>{};

    for (final token in {...chosenWeight.keys, ...rejectedWeight.keys}) {
      final c = chosenWeight[token] ?? 0;
      final r = rejectedWeight[token] ?? 0;
      final n = c + r;
      if ((sightings[token] ?? 0) < tuning.minTokenFreq) continue;
      final rate = c / n;
      final raw = rate >= baseline
          ? (rate - baseline) / (1 - baseline)
          : (rate - baseline) / baseline;
      // Shrink toward neutral in proportion to how little evidence there is.
      final obs = (sightings[token] ?? 0).toDouble();
      final confidence =
          tuning.shrinkageK <= 0 ? 1.0 : obs / (obs + tuning.shrinkageK);
      scores[token] = raw * confidence;
    }

    return scores;
  }

  /// Learn menu type preference from historical pick frequency.
  static Map<String, double> _buildMenuTypeModel(List<dynamic> data) {
    final typeChosen = <String, double>{};
    final typeTotal = <String, double>{};

    for (final day in data) {
      final weight = _weightOf(day as Map);
      for (final opt in day['options'] as List) {
        final name = normalizeMenuName((opt as Map)['menu_name'] as String);
        typeTotal[name] = (typeTotal[name] ?? 0) + weight;
        if (opt['chosen'] as bool) {
          typeChosen[name] = (typeChosen[name] ?? 0) + weight;
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
  static Map<String, double> _buildRatingModel(
      List<dynamic> ratings, PredictorTuning tuning) {
    final tokenSums = <String, double>{};
    final tokenCounts = <String, int>{};

    for (final r in ratings) {
      if (r is! Map<String, dynamic>) continue;
      final desc = r['description'] as String? ?? '';
      // Defensive parse: stored ratings are int, but a hand-edited or
      // legacy-format file could serialize as a string. `as int?` would
      // throw on a String. Coerce via toString+tryParse instead and fall
      // back to neutral (3) on anything unrecognized.
      final rating = int.tryParse('${r['rating']}') ?? 3;
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
        t: (tokenSums[t]! / tokenCounts[t]!) *
            (tuning.ratingShrinkageK <= 0
                ? 1.0
                : tokenCounts[t]! / (tokenCounts[t]! + tuning.ratingShrinkageK)),
    };
  }

  /// Normalized menu names the model has any history for.
  ///
  /// A new school year renames and reshuffles menus. `normalizeMenuName`
  /// absorbs a changed price, but a menu that is genuinely new — or renamed
  /// beyond the bracket — carries no history at all, and the model will
  /// quietly score it 0 rather than admit it has never seen it.
  Set<String> get knownMenus => _menuTypeScores.keys.toSet();

  /// How many tokens survived into the keyword model. Used by the
  /// evaluation harness to show what a frequency cutoff costs.
  int get vocabularySize => _keywordScores.length;

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

    return _effectiveWKeyword * keywordScore +
        _tuning.wMenuType * menuScore +
        _tuning.wManual * manualScore +
        _tuning.wRating * ratingScore;
  }

  /// Rank a day's available options and report how clear the win was.
  ///
  /// The UI presented every pick with the same confident badge, whether the
  /// model preferred it by a mile or by a rounding error. On a thin model
  /// near-ties are common, and a coin flip dressed as a decision is the kind
  /// of thing that quietly costs the user their trust the first time they
  /// notice it.
  /// [isCandidate] decides what counts as pickable. It defaults to
  /// `available` only, which is what the unattended submit must use — an
  /// already-ordered day is the user's choice and must not be overwritten.
  /// The menu screen passes a wider predicate because it also suggests
  /// improvements on days the school has already defaulted.
  DayRanking rankDay(
    List<MealOption> options, {
    bool Function(MealOption)? isCandidate,
  }) {
    final candidate = isCandidate ?? (o) => o.status == 'available';
    final scored = <({String id, String name, double score})>[
      for (final opt in options)
        if (candidate(opt))
          (
            id: opt.menuId,
            name: opt.menuName,
            score: scoreOption(opt.menuName, opt.description)
          )
    ]..sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) return const DayRanking.none();
    if (scored.length == 1) {
      return DayRanking(
        menuId: scored.first.id,
        score: scored.first.score,
        runnerUpId: null,
        runnerUpName: null,
        margin: double.infinity,
        relativeMargin: 1,
      );
    }

    final best = scored.first;
    final second = scored[1];
    final worst = scored.last;
    final spread = best.score - worst.score;
    final margin = best.score - second.score;

    return DayRanking(
      menuId: best.id,
      score: best.score,
      runnerUpId: second.id,
      runnerUpName: second.name,
      margin: margin,
      // Judged against the day's own spread rather than an absolute number,
      // because the scale of these scores shifts with how much the model has
      // learned. Everything within a tenth of the day's range is a tie.
      relativeMargin: spread <= 0 ? 0 : margin / spread,
    );
  }

  /// Break a score down into the signals that produced it.
  ///
  /// The model is opaque from the outside: it surfaces one number and a
  /// highlighted card, and when it is wrong there is no way to tell whether
  /// it misread the food, is coasting on a menu habit, or is acting on a
  /// keyword the user set months ago and forgot. This returns the same
  /// arithmetic [scoreOption] performs, labelled.
  PickExplanation explain(String menuName, String description) {
    final tokens = tokenize(description);
    final descLower = description.toLowerCase();
    final normName = normalizeMenuName(menuName);

    final known = <MapEntry<String, double>>[
      for (final t in tokens)
        if (_keywordScores.containsKey(t))
          MapEntry(t, _keywordScores[t]!)
    ];
    final keywordScore = known.isEmpty
        ? 0.0
        : known.map((e) => e.value).reduce((a, b) => a + b) / known.length;

    var menuScore = _menuTypeScores[normName] ?? 0.0;
    if (_manualMenuScores.isNotEmpty) {
      menuScore = 0.7 * menuScore + 0.3 * (_manualMenuScores[normName] ?? 0.0);
    }

    final liked = [
      for (final kw in _likedKeywords)
        if (descLower.contains(kw)) kw
    ];
    final disliked = [
      for (final kw in _dislikedKeywords)
        if (descLower.contains(kw)) kw
    ];
    final manualScore = liked.length - disliked.length.toDouble();

    final ratingKnown = <MapEntry<String, double>>[
      for (final t in tokens)
        if (_ratingKeywordScores.containsKey(t))
          MapEntry(t, _ratingKeywordScores[t]!)
    ];
    final ratingScore = ratingKnown.isEmpty
        ? 0.0
        : ratingKnown.map((e) => e.value).reduce((a, b) => a + b) /
            ratingKnown.length;

    final drivers = [...known]
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    final factors = <ScoreFactor>[
      ScoreFactor(
        kind: FactorKind.keyword,
        contribution: _effectiveWKeyword * keywordScore,
        terms: [for (final e in drivers.take(4)) (e.key, e.value)],
        note: known.isEmpty
            ? 'Nobene znane besede'
            : 'Iz ${known.length} znanih besed',
      ),
      ScoreFactor(
        kind: FactorKind.menuType,
        contribution: _tuning.wMenuType * menuScore,
        terms: const [],
        // The rate the user actually picks this menu, which is the whole
        // content of this signal. Repeating the menu's own name here told
        // the reader nothing they could not see in the title.
        note: _menuTypeScores.containsKey(normName)
            ? 'Izbereš ga v ${(_menuTypeScores[normName]! * 100).round()} % primerov'
            : 'Ni zgodovine za ta meni',
      ),
      ScoreFactor(
        kind: FactorKind.manual,
        contribution: _tuning.wManual * manualScore,
        terms: [
          for (final k in liked) (k, 1.0),
          for (final k in disliked) (k, -1.0),
        ],
        note: liked.isEmpty && disliked.isEmpty ? 'Ni zadetkov' : '',
      ),
      ScoreFactor(
        kind: FactorKind.rating,
        contribution: _tuning.wRating * ratingScore,
        terms: const [],
        note: ratingKnown.isEmpty
            ? 'Ni ocen za te besede'
            : 'Iz ${ratingKnown.length} ocenjenih besed',
      ),
    ]..sort((a, b) => b.contribution.abs().compareTo(a.contribution.abs()));

    return PickExplanation(
      total: factors.fold(0.0, (sum, f) => sum + f.contribution),
      factors: factors,
      keywordWeight: _effectiveWKeyword,
      maxKeywordWeight: _tuning.wKeyword,
    );
  }

  /// Score all options for a day. Returns menuId → score.
  Map<String, double> scoreDay(List<MealOption> options) => {
        for (final opt in options)
          opt.menuId: scoreOption(opt.menuName, opt.description),
      };

  /// Pick the best available option for a day. Returns menuId or null.
  ///
  /// Only `available` options are candidates: an `ordered` day already has
  /// the user's choice on it and the callers that use this (auto-submit,
  /// the widget) must not overwrite one.
  String? pickBest(List<MealOption> options) => _best(options).menuId;

  /// Pick the best option, or recommend Odjava when every available option
  /// is strongly negative.
  ///
  /// Odjava is recommended when:
  ///   - at least one option was scored (so we're not on an unseen menu), AND
  ///   - the best score is at or below [kOdjavaScoreThreshold].
  ///
  /// The threshold is negative, so this implicitly requires that no positive
  /// option exists — any positive score would beat the gate.
  PickResult pickBestOrOdjava(List<MealOption> options) {
    final best = _best(options);
    if (best.menuId == null) return const PickResult.none();
    if (best.bestScore! <= kOdjavaScoreThreshold) {
      return PickResult.odjava(bestScore: best.bestScore!);
    }
    return best;
  }

  /// The single scan both pick methods share. They previously each carried
  /// their own copy of this loop, so a change to what counts as selectable
  /// had to be made twice — and the two could silently disagree.
  PickResult _best(List<MealOption> options) {
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

/// Which signal a [ScoreFactor] came from.
enum FactorKind { keyword, menuType, manual, rating }

extension FactorKindLabel on FactorKind {
  /// Slovenian label for the UI.
  String get label => switch (this) {
        FactorKind.keyword => 'Sestavine',
        FactorKind.menuType => 'Navada pri meniju',
        FactorKind.manual => 'Tvoje nastavitve',
        FactorKind.rating => 'Tvoje ocene',
      };
}

/// One signal's weighted contribution to an option's score.
class ScoreFactor {
  final FactorKind kind;

  /// Already multiplied by the signal's weight, so these sum to the total.
  final double contribution;

  /// The individual words behind this factor, strongest first.
  final List<(String, double)> terms;

  /// Short human note, e.g. how many known words fed the average.
  final String note;

  const ScoreFactor({
    required this.kind,
    required this.contribution,
    required this.terms,
    required this.note,
  });
}

/// Why the model scored an option the way it did.
class PickExplanation {
  final double total;

  /// Signals, strongest absolute contribution first.
  final List<ScoreFactor> factors;

  /// The keyword weight actually applied, after evidence scaling.
  final double keywordWeight;

  /// The weight it would reach with plenty of training data.
  final double maxKeywordWeight;

  const PickExplanation({
    required this.total,
    required this.factors,
    required this.keywordWeight,
    required this.maxKeywordWeight,
  });

  /// How far along the keyword signal is toward its full influence, 0..1.
  /// Doubles as an honest "how much does this model actually know yet".
  double get keywordMaturity =>
      maxKeywordWeight <= 0 ? 0 : keywordWeight / maxKeywordWeight;
}

/// How decisively the model preferred one option on a given day.
class DayRanking {
  final String? menuId;
  final double? score;
  final String? runnerUpId;
  final String? runnerUpName;

  /// Raw gap to the runner-up.
  final double margin;

  /// [margin] as a fraction of the day's full score range, 0..1.
  final double relativeMargin;

  const DayRanking({
    required this.menuId,
    required this.score,
    required this.runnerUpId,
    required this.runnerUpName,
    required this.margin,
    required this.relativeMargin,
  });

  const DayRanking.none()
      : menuId = null,
        score = null,
        runnerUpId = null,
        runnerUpName = null,
        margin = 0,
        relativeMargin = 0;

  /// Below this the top two are close enough that presenting the winner as
  /// a decision overstates what the model actually knows.
  static const closeThreshold = 0.10;

  bool get isClose => menuId != null && relativeMargin < closeThreshold;
}

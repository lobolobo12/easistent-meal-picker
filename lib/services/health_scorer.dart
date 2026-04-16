import '../models/meal_option.dart';

// ── Food‑group keyword rules ──

/// Each keyword maps to a food group and a raw weight.
///   positive  → +1
///   neutral   →  0
///   negative  → −1

enum _FoodGroup {
  vegetable,
  protein,
  wholeGrain,
  legume,
  fruit,
  dairy,
  starch,
  fried,
  processed,
  sugary,
}

const _groupWeight = <_FoodGroup, int>{
  _FoodGroup.vegetable: 1,
  _FoodGroup.protein: 1,
  _FoodGroup.wholeGrain: 1,
  _FoodGroup.legume: 1,
  _FoodGroup.fruit: 1,
  _FoodGroup.dairy: 0,
  _FoodGroup.starch: 0,
  _FoodGroup.fried: -1,
  _FoodGroup.processed: -1,
  _FoodGroup.sugary: -1,
};

/// Slovenian keyword → food group.
/// Substrings are matched so "piščančje" covers "piščančji", "piščančja", etc.
const _keywords = <String, _FoodGroup>{
  // vegetables
  'solata': _FoodGroup.vegetable,
  'zelenjava': _FoodGroup.vegetable,
  'brokoli': _FoodGroup.vegetable,
  'koruza': _FoodGroup.vegetable,
  'paprika': _FoodGroup.vegetable,
  'paradižnik': _FoodGroup.vegetable,
  'špinač': _FoodGroup.vegetable, // špinača
  'blitva': _FoodGroup.vegetable,
  'korenje': _FoodGroup.vegetable,
  'buča': _FoodGroup.vegetable, // buča, bučka
  'bučka': _FoodGroup.vegetable,
  'grah': _FoodGroup.vegetable,
  'zelje': _FoodGroup.vegetable,
  'kumar': _FoodGroup.vegetable, // kumara, kumarice
  'radič': _FoodGroup.vegetable,
  'čebula': _FoodGroup.vegetable,
  'por': _FoodGroup.vegetable,
  'peso': _FoodGroup.vegetable, // pesa
  'olive': _FoodGroup.vegetable,

  // protein
  'piščančj': _FoodGroup.protein, // piščančje, piščančji, ...
  'piščanc': _FoodGroup.protein,
  'govej': _FoodGroup.protein, // goveja, goveje, goveji
  'puranj': _FoodGroup.protein, // puranje, puranji
  'telet': _FoodGroup.protein, // teletina
  'teleč': _FoodGroup.protein, // telečja, telečje
  'svinjsk': _FoodGroup.protein, // svinjska, svinjsko
  'jajc': _FoodGroup.protein, // jajce, jajca
  'rib': _FoodGroup.protein, // riba, ribje, ribi
  'tuna': _FoodGroup.protein,
  'losos': _FoodGroup.protein,
  'postrv': _FoodGroup.protein,
  'skuš': _FoodGroup.protein, // skuša
  'zrezek': _FoodGroup.protein,

  // whole grains
  'polnozrnat': _FoodGroup.wholeGrain, // polnozrnata, polnozrnati
  'ajdov': _FoodGroup.wholeGrain, // ajdova, ajdovi
  'ovsen': _FoodGroup.wholeGrain, // ovsena, ovseni
  'ječmen': _FoodGroup.wholeGrain, // ječmenova
  'prosena': _FoodGroup.wholeGrain,
  'kvinoja': _FoodGroup.wholeGrain,

  // legumes
  'leča': _FoodGroup.legume,
  'lečo': _FoodGroup.legume,
  'fižol': _FoodGroup.legume,
  'čičerik': _FoodGroup.legume, // čičerika

  // fruit
  'jabolko': _FoodGroup.fruit,
  'jabolč': _FoodGroup.fruit, // jabolčna, jabolčni
  'hruška': _FoodGroup.fruit,
  'banana': _FoodGroup.fruit,
  'jagod': _FoodGroup.fruit, // jagoda, jagode
  'breskov': _FoodGroup.fruit, // breskova, breskove
  'pomaran': _FoodGroup.fruit, // pomaranča, pomarančni
  'borovnic': _FoodGroup.fruit,
  'sadje': _FoodGroup.fruit,
  'sadni': _FoodGroup.fruit,

  // dairy (neutral)
  'sir': _FoodGroup.dairy,
  'jogurt': _FoodGroup.dairy,
  'mleko': _FoodGroup.dairy,
  'skuta': _FoodGroup.dairy,
  'skutin': _FoodGroup.dairy, // skutina, skutini
  'smetana': _FoodGroup.dairy,
  'maslo': _FoodGroup.dairy,

  // standard carbs (neutral)
  'riž': _FoodGroup.starch,
  'testeni': _FoodGroup.starch, // testenine, testenini
  'kruh': _FoodGroup.starch,
  'krompir': _FoodGroup.starch,
  'pire': _FoodGroup.starch,
  'njoki': _FoodGroup.starch,
  'cmoki': _FoodGroup.starch,
  'žlikrof': _FoodGroup.starch, // žlikrofi
  'palačink': _FoodGroup.starch, // palačinka, palačinke
  'rezanc': _FoodGroup.starch, // rezanci

  // fried (negative)
  'ocvrt': _FoodGroup.fried, // ocvrt, ocvrta, ocvrti
  'pohan': _FoodGroup.fried, // pohano, pohana, pohani
  'cvrtj': _FoodGroup.fried, // cvrtje
  'prženi': _FoodGroup.fried,
  'pržena': _FoodGroup.fried,
  'prženo': _FoodGroup.fried,

  // processed (negative)
  'hrenovk': _FoodGroup.processed, // hrenovka, hrenovke
  'salam': _FoodGroup.processed, // salama, salame
  'parizer': _FoodGroup.processed,
  'kobas': _FoodGroup.processed, // klobasa — matched via substring
  'klobas': _FoodGroup.processed,
  'paštet': _FoodGroup.processed, // pašteta
  'mortadel': _FoodGroup.processed,
  'viršli': _FoodGroup.processed,

  // heavy / sugary (negative)
  'čokolad': _FoodGroup.sugary, // čokolada, čokoladna, čokoladno
  'puding': _FoodGroup.sugary,
  'bombeta': _FoodGroup.sugary,
  'nutella': _FoodGroup.sugary,
  'buhteljn': _FoodGroup.sugary,
  'torta': _FoodGroup.sugary,
  'krofi': _FoodGroup.sugary, // krofi, krofov
  'sladoled': _FoodGroup.sugary,
  'kremšnit': _FoodGroup.sugary, // kremšnita
  'marmelad': _FoodGroup.sugary,
};

// ── Scoring ──

/// Result of scoring a single meal option.
class HealthScore {
  /// 1–10 score (10 = healthiest).
  final int score;

  const HealthScore._(this.score);
}

/// Scores a single meal option description on a 1–10 scale.
///
/// Algorithm:
///   1. Tokenize, then substring‑match against keyword rules.
///   2. Sum positive (+1 each), neutral (0), negative (−1 each) hits.
///   3. Award a diversity bonus when ≥3 distinct positive groups appear.
///   4. Map raw sum → 1–10 via a clamped linear scale.
HealthScore scoreMeal(String description) {
  final text = description.toLowerCase();
  final detected = <_FoodGroup>{};

  // Match every keyword that appears as a substring in the description.
  for (final entry in _keywords.entries) {
    if (text.contains(entry.key)) {
      detected.add(entry.value);
    }
  }

  // Sum weights of detected groups.
  var raw = 0;
  for (final g in detected) {
    raw += _groupWeight[g]!;
  }

  // Diversity bonus: 3+ distinct positive groups → +1.
  final positiveCount = detected.where((g) => _groupWeight[g]! > 0).length;
  if (positiveCount >= 3) raw += 1;

  // Map raw score to 1–10.
  // Expected raw range roughly −3..+6.  We clamp and linearly interpolate.
  // raw ≤ −2 → 1,  raw ≥ 5 → 10.
  const rawMin = -2;
  const rawMax = 5;
  final normalized = (raw - rawMin) / (rawMax - rawMin); // 0.0 .. 1.0
  final score = (normalized * 9 + 1).round().clamp(1, 10);

  return HealthScore._(score);
}

/// Score every option for a single day.
Map<String, int> scoreDayOptions(List<MealOption> options) {
  return {
    for (final opt in options)
      opt.menuId: scoreMeal(opt.description).score,
  };
}

// ── Weekly variety penalty ──

/// Given an ordered list of days (date → chosen description), returns a
/// per‑date variety penalty (0 = fine, negative = repetitive).
///
/// Rules:
///   • If the dominant food group on two consecutive days is the same → −1
///     for the second day.
///   • Three consecutive days with the same dominant group → −2 for the
///     third day (cumulative).
Map<String, int> weeklyVarietyPenalty(Map<String, String> dayDescriptions) {
  final sortedDates = dayDescriptions.keys.toList()..sort();
  final penalties = <String, int>{};

  _FoodGroup? prevDominant;
  int streak = 0;

  for (final date in sortedDates) {
    final desc = dayDescriptions[date]!;
    final dominant = _dominantGroup(desc);

    int penalty = 0;
    if (dominant != null && dominant == prevDominant) {
      streak++;
      // −1 for 2nd consecutive day, −2 for 3rd+
      penalty = streak >= 2 ? -2 : -1;
    } else {
      streak = 0;
    }

    penalties[date] = penalty;
    prevDominant = dominant;
  }

  return penalties;
}

/// Applies variety penalties to per‑day scores.
/// Returns adjusted scores clamped to 1–10.
Map<String, int> adjustScoresForVariety({
  required Map<String, int> baseScores,
  required Map<String, String> dayDescriptions,
}) {
  final penalties = weeklyVarietyPenalty(dayDescriptions);
  return {
    for (final entry in baseScores.entries)
      entry.key: (entry.value + (penalties[entry.key] ?? 0)).clamp(1, 10),
  };
}

/// Human‑readable Slovenian labels for display.
const foodGroupLabels = <String, String>{
  'vegetable': 'Zelenjava',
  'protein': 'Beljakovine',
  'wholeGrain': 'Polnozrnato',
  'legume': 'Strocnice',
  'fruit': 'Sadje',
  'dairy': 'Mlecni izdelki',
  'starch': 'Skrob / OH',
  'fried': 'Ocvrto',
  'processed': 'Predelano',
  'sugary': 'Sladko',
};

/// Colors for each food group (for charts).
const foodGroupColors = <String, int>{
  'vegetable': 0xFF68d391, // green
  'protein': 0xFFf6ad55, // amber
  'wholeGrain': 0xFFfbd38d, // yellow
  'legume': 0xFF4fd1c5, // teal
  'fruit': 0xFFfc8181, // red
  'dairy': 0xFF63b3ed, // blue
  'starch': 0xFFb794f6, // purple
  'fried': 0xFFfc8181, // red
  'processed': 0xFFfc8181, // red
  'sugary': 0xFFd6bcfa, // mauve
};

/// Detect food groups present in a description.
/// Returns a set of group key strings (e.g. 'vegetable', 'protein').
Set<String> detectFoodGroups(String description) {
  final text = description.toLowerCase();
  final detected = <_FoodGroup>{};

  for (final entry in _keywords.entries) {
    if (text.contains(entry.key)) {
      detected.add(entry.value);
    }
  }

  return detected.map((g) => g.name).toSet();
}

/// Find the highest‑weighted food group in a description.
/// Prefers positive groups; falls back to neutral; ignores negative.
_FoodGroup? _dominantGroup(String description) {
  final text = description.toLowerCase();
  final detected = <_FoodGroup>{};

  for (final entry in _keywords.entries) {
    if (text.contains(entry.key)) {
      detected.add(entry.value);
    }
  }

  if (detected.isEmpty) return null;

  // Pick the group with the highest weight; among ties, pick first found.
  _FoodGroup? best;
  var bestWeight = -999;
  for (final g in detected) {
    final w = _groupWeight[g]!;
    if (w > bestWeight) {
      bestWeight = w;
      best = g;
    }
  }
  return best;
}

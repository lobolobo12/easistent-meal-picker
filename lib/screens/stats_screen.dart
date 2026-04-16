import 'dart:math';

import 'package:flutter/material.dart';

import '../services/health_scorer.dart';
import '../services/submission_log.dart';
import '../services/training_store.dart';
import '../theme.dart';

const _monthNames = <int, String>{
  1: 'Jan',
  2: 'Feb',
  3: 'Mar',
  4: 'Apr',
  5: 'Maj',
  6: 'Jun',
  7: 'Jul',
  8: 'Avg',
  9: 'Sep',
  10: 'Okt',
  11: 'Nov',
  12: 'Dec',
};

const _navBarPad = 90.0;

/// Comprehensive Slovenian stop words: prepositions, conjunctions, adjectives,
/// articles, verbs, and other non-food filler words.
const _statsStopWords = <String>{
  // prepositions
  'v', 'z', 's', 'na', 'po', 'za', 'pri', 'ob', 'iz', 'do', 'od', 'k',
  'med', 'nad', 'pod', 'pred', 'skozi', 'proti', 'brez', 'okrog',
  // conjunctions & particles
  'in', 'ki', 'ter', 'ali', 'ko', 'če', 'da', 'ker', 'saj', 'pa', 'tudi',
  'se', 'je', 'so', 'ni', 'bo', 'bi', 'ne', 'že', 'le', 'sicer',
  // common adjectives (non-food-specific)
  'navaden', 'navadna', 'navadno', 'navadni',
  'svež', 'sveža', 'sveže', 'sveži',
  'topel', 'topla', 'toplo', 'topli',
  'hladen', 'hladna', 'hladno', 'hladni',
  'domač', 'domača', 'domače', 'domači',
  'različen', 'različna', 'različno', 'različni', 'različne',
  'mesen', 'mesna', 'mesno', 'mesni',
  'mlet', 'mleta', 'mleto', 'mleti',
  // generic serving/portion words
  'porcija', 'kosilo', 'malica', 'obrok', 'hrana',
  'izbira', 'dnevna', 'dnevni', 'dnevno',
  // allergen / label words
  'vsebuje', 'izdelek', 'sledi', 'laktozo', 'alergeni',
  // pronouns & misc
  'to', 'ta', 'te', 'ti', 'teh', 'tem', 'tega',
  'eno', 'ena', 'en',
  'vse', 'vsi', 'vsa',
  'kot', 'lahko', 'nekaj', 'več', 'zelo', 'bolj',
  // common non-food verbs
  'dušena', 'dušeni', 'dušeno', 'dušene',
  'pečena', 'pečeni', 'pečeno', 'pečene',
  'kuhana', 'kuhani', 'kuhano', 'kuhane',
  'pržena', 'prženi', 'prženo', 'pržene',
  'narezana', 'narezani', 'narezano', 'narezane',
  'posuta', 'posuti', 'posuto', 'posute',
  'prelita', 'preliti', 'prelito', 'prelite',
  'polita', 'politi', 'polito', 'polite',
  // generic prep words
  'kis', 'sol', 'olje', 'voda', 'sladkor',
};

/// Words that are typically adjectives modifying food — they should only
/// appear as part of a bigram, never standalone.
const _adjectiveWords = <String>{
  'goveja', 'goveje', 'goveji', 'govejo',
  'piščančja', 'piščančje', 'piščančji', 'piščančjo',
  'svinjska', 'svinjske', 'svinjski', 'svinjsko',
  'puranja', 'puranje', 'puranji', 'puranjo',
  'teleča', 'teleče', 'teleči', 'telečo',
  'ribja', 'ribje', 'ribji', 'ribjo',
  'zelenjavna', 'zelenjavne', 'zelenjavni', 'zelenjavno',
  'paradiznikova', 'paradiznikove', 'paradiznikovi', 'paradiznikovo',
  'gobova', 'gobove', 'gobovi', 'gobovo',
  'jabolčna', 'jabolčne', 'jabolčni', 'jabolčno',
  'skutina', 'skutine', 'skutini', 'skutino',
  'sirov', 'sirova', 'sirove', 'sirovi', 'sirovo',
  'čokoladna', 'čokoladne', 'čokoladni', 'čokoladno',
  'vanilijev', 'vaniljeva', 'vaniljeve', 'vaniljevi', 'vaniljevo',
  'kremna', 'kremne', 'kremni', 'kremno',
  'jogurtov', 'jogurtova', 'jogurtove', 'jogurtovi', 'jogurtovo',
  'česnjakov', 'česnjakova', 'česnjakove', 'česnjakovi', 'česnjakovo',
  'ocvrt', 'ocvrta', 'ocvrte', 'ocvrti', 'ocvrto',
  'pisan', 'pisana', 'pisane', 'pisani', 'pisano',
  'mešana', 'mešane', 'mešani', 'mešano',
};

/// Extract food phrases (bigrams and unigrams) from a meal description.
/// Prefers keeping adjective+noun bigrams together as one item.
List<String> _extractFoodPhrases(String description) {
  var text = description.toLowerCase();
  // Strip allergen parentheticals
  text = text.replaceAll(RegExp(r'\([^)]*\)'), '');
  final words = RegExp(r'[a-zčšžćđ]+')
      .allMatches(text)
      .map((m) => m.group(0)!)
      .where((w) => w.length >= 3)
      .toList();

  final phrases = <String>[];
  final usedIndices = <int>{};

  // First pass: extract bigrams where first word is an adjective
  for (var i = 0; i < words.length - 1; i++) {
    final w1 = words[i];
    final w2 = words[i + 1];
    if (_adjectiveWords.contains(w1) && !_statsStopWords.contains(w2)) {
      phrases.add('$w1 $w2');
      usedIndices.addAll([i, i + 1]);
      i++; // skip next word since it's consumed
    }
  }

  // Second pass: remaining words that are real food tokens
  for (var i = 0; i < words.length; i++) {
    if (usedIndices.contains(i)) continue;
    final w = words[i];
    if (_statsStopWords.contains(w) || _adjectiveWords.contains(w)) continue;
    phrases.add(w);
  }

  return phrases;
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isLoading = true;

  int _aiTotal = 0;
  int _aiKept = 0;
  final Map<String, int> _menuTypeCounts = {};
  int _totalSubmissions = 0;
  final List<MapEntry<String, double>> _topKeywords = [];
  final Map<String, int> _monthlyCounts = {};

  // Health stats
  /// ISO‑week label → average health score (last 4 weeks).
  final List<MapEntry<String, double>> _weeklyHealthScores = [];
  /// Food group key → count of appearances in submitted meals.
  final Map<String, int> _foodGroupCounts = {};
  /// Suggestion text (empty if none).
  String _healthSuggestion = '';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);

    final log = await SubmissionLog.load();
    final trainingData = await TrainingStore.load();

    _aiTotal = 0;
    _aiKept = 0;
    _menuTypeCounts.clear();
    _monthlyCounts.clear();
    _totalSubmissions = 0;

    for (final entry in log) {
      final menuName = entry['menuName'] as String? ?? '';
      if (menuName == 'Odjava') continue;

      _totalSubmissions++;
      _menuTypeCounts[menuName] = (_menuTypeCounts[menuName] ?? 0) + 1;

      final dateStr = entry['date'] as String? ?? '';
      if (dateStr.length >= 7) {
        final monthKey = dateStr.substring(0, 7);
        _monthlyCounts[monthKey] = (_monthlyCounts[monthKey] ?? 0) + 1;
      }

      final aiPickName = entry['aiPickMenuName'] as String?;
      if (aiPickName != null) {
        _aiTotal++;
        if (menuName == aiPickName) _aiKept++;
      }
    }

    _topKeywords.clear();
    final chosenCounts = <String, int>{};
    final totalCounts = <String, int>{};

    for (final day in trainingData) {
      for (final opt in (day as Map)['options'] as List) {
        final phrases = _extractFoodPhrases((opt as Map)['description'] as String);
        final chosen = opt['chosen'] as bool;
        for (final t in phrases) {
          totalCounts[t] = (totalCounts[t] ?? 0) + 1;
          if (chosen) chosenCounts[t] = (chosenCounts[t] ?? 0) + 1;
        }
      }
    }

    final scored = <String, double>{};
    for (final t in totalCounts.keys) {
      final c = chosenCounts[t] ?? 0;
      final total = totalCounts[t]!;
      if (total < 5 || c < 2) continue;
      scored[t] = c / total;
    }
    final sorted = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _topKeywords.addAll(sorted.take(10));

    // ── Health stats ──
    _weeklyHealthScores.clear();
    _foodGroupCounts.clear();
    _healthSuggestion = '';

    // Collect health scores + food groups from submissions (non‑odjava).
    final weekScores = <String, List<int>>{}; // "YYYY-Wnn" → scores
    final now = DateTime.now();
    final fourWeeksAgo = now.subtract(const Duration(days: 28));

    for (final entry in log) {
      final menuName = entry['menuName'] as String? ?? '';
      if (menuName == 'Odjava' || menuName == 'Odsoten') continue;

      final desc = entry['description'] as String? ?? '';
      if (desc.isEmpty) continue;

      final dateStr = entry['date'] as String? ?? '';
      DateTime? date;
      try {
        date = DateTime.parse(dateStr);
      } catch (_) {
        continue;
      }

      // Food‑group counts (all time)
      final groups = detectFoodGroups(desc);
      for (final g in groups) {
        _foodGroupCounts[g] = (_foodGroupCounts[g] ?? 0) + 1;
      }

      // Weekly health scores (last 4 weeks)
      if (date.isAfter(fourWeeksAgo)) {
        final hs = scoreMeal(desc).score;
        final weekNum = _isoWeekNumber(date);
        final key = '${date.year}-T$weekNum';
        weekScores.putIfAbsent(key, () => []).add(hs);
      }
    }

    // Average per week, sorted chronologically
    final weekKeys = weekScores.keys.toList()..sort();
    for (final wk in weekKeys) {
      final scores = weekScores[wk]!;
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      _weeklyHealthScores.add(MapEntry(wk, avg));
    }

    // Generate suggestion based on food group balance
    final positiveGroups = ['vegetable', 'protein', 'wholeGrain', 'legume', 'fruit'];
    final totalPositive = positiveGroups.fold<int>(
        0, (sum, g) => sum + (_foodGroupCounts[g] ?? 0));

    if (totalPositive > 0) {
      // Find the weakest positive group
      String? weakest;
      int weakestCount = 999999;
      for (final g in positiveGroups) {
        final c = _foodGroupCounts[g] ?? 0;
        if (c < weakestCount) {
          weakestCount = c;
          weakest = g;
        }
      }

      final fried = _foodGroupCounts['fried'] ?? 0;
      final processed = _foodGroupCounts['processed'] ?? 0;
      final sugary = _foodGroupCounts['sugary'] ?? 0;
      final negativeTotal = fried + processed + sugary;

      if (negativeTotal > totalPositive * 0.4) {
        _healthSuggestion =
            'Priporocilo: zmanjsaj ocvrte in predelane jedi ta teden.';
      } else if (weakest != null) {
        final label = foodGroupLabels[weakest]?.toLowerCase() ?? weakest;
        final suggestion = {
          'vegetable': 'Priporocilo: izberi vec zelenjave ta teden.',
          'protein': 'Priporocilo: dodaj vec beljakovinskih jedi ta teden.',
          'wholeGrain': 'Priporocilo: poskusi polnozrnate opcije ta teden.',
          'legume': 'Priporocilo: vkljuci strocnice (leca, fizol) ta teden.',
          'fruit': 'Priporocilo: dodaj vec sadja ta teden.',
        };
        _healthSuggestion = suggestion[weakest] ??
            'Priporocilo: izberi vec $label ta teden.';
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Statistika'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Osveži',
            onPressed: _isLoading ? null : _loadStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _totalSubmissions == 0 && _topKeywords.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, _navBarPad),
                    children: [
                      if (_aiTotal > 0) _buildAiAccuracy(),
                      if (_menuTypeCounts.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildMenuTypes(),
                      ],
                      if (_topKeywords.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildTopKeywords(),
                      ],
                      if (_weeklyHealthScores.isNotEmpty ||
                          _foodGroupCounts.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildHealth(),
                      ],
                      if (_monthlyCounts.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildMonthly(),
                      ],
                      if (_aiTotal == 0 && _totalSubmissions > 0) ...[
                        const SizedBox(height: 14),
                        _buildAiNoData(),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 56, color: kTextMuted),
            SizedBox(height: 16),
            Text('Še ni podatkov',
                style: TextStyle(fontSize: 18, color: kTextMuted)),
            SizedBox(height: 8),
            Text('Začni z uporabo aplikacije!',
                style: TextStyle(fontSize: 13, color: kTextMuted),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── AI Accuracy card ──

  Widget _buildAiAccuracy() {
    final pct = _aiTotal > 0 ? (_aiKept / _aiTotal * 100) : 0.0;
    final overridden = _aiTotal - _aiKept;
    final color = pct >= 70
        ? kAccentGreen
        : pct >= 40
            ? kAccentYellow
            : kAccentRed;

    return _SectionCard(
      title: 'AI natancnost',
      icon: Icons.auto_awesome,
      iconColor: kAccentMauve,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w700,
              color: color,
              shadows: [
                Shadow(color: color.withAlpha(100), blurRadius: 16),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Obdrzano $_aiKept / $_aiTotal AI izbir',
            style: const TextStyle(fontSize: 13, color: kTextSecondary),
          ),
          const SizedBox(height: 12),
          _GlassProgressBar(
            value: _aiTotal > 0 ? _aiKept / _aiTotal : 0,
            color: color,
            height: 10,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MiniStat(
                  label: 'Obdrzano', value: '$_aiKept', color: kAccentGreen),
              _MiniStat(
                  label: 'Spremenjeno',
                  value: '$overridden',
                  color: kAccentAmber),
              _MiniStat(
                  label: 'Skupaj', value: '$_aiTotal', color: kAccentBlue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiNoData() {
    return _SectionCard(
      title: 'AI natancnost',
      icon: Icons.auto_awesome,
      iconColor: kAccentMauve,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Podatki o AI natancnosti bodo na voljo po naslednjih oddajah.',
          style: TextStyle(fontSize: 13, color: kTextMuted),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── Menu types card ──

  Widget _buildMenuTypes() {
    final sorted = _menuTypeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCount = sorted.isNotEmpty ? sorted.first.value : 1;

    return _SectionCard(
      title: 'Najbolj izbrani meniji',
      icon: Icons.restaurant,
      iconColor: kAccentAmber,
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (var i = 0; i < sorted.length; i++)
            _MenuTypeRow(
              name: sorted[i].key,
              count: sorted[i].value,
              total: _totalSubmissions,
              maxCount: maxCount,
              color: menuColor(sorted[i].key),
            ),
        ],
      ),
    );
  }

  // ── Top keywords card ──

  Widget _buildTopKeywords() {
    return _SectionCard(
      title: 'Najljubse jedi',
      icon: Icons.favorite,
      iconColor: kAccentRed,
      child: Column(
        children: [
          const SizedBox(height: 6),
          for (var i = 0; i < _topKeywords.length; i++)
            _KeywordRow(
              rank: i + 1,
              keyword: _topKeywords[i].key,
              score: _topKeywords[i].value,
            ),
        ],
      ),
    );
  }

  // ── Monthly breakdown card ──

  Widget _buildMonthly() {
    final sortedMonths = _monthlyCounts.keys.toList()..sort();
    final maxCount = _monthlyCounts.values.reduce(max);

    return _SectionCard(
      title: 'Mesecni pregled',
      icon: Icons.calendar_month,
      iconColor: kAccentBlue,
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final month in sortedMonths)
            _MonthRow(
              label: _formatMonth(month),
              count: _monthlyCounts[month]!,
              maxCount: maxCount,
            ),
        ],
      ),
    );
  }

  String _formatMonth(String yyyyMm) {
    try {
      final parts = yyyyMm.split('-');
      final year = parts[0];
      final month = int.parse(parts[1]);
      return '${_monthNames[month] ?? parts[1]} $year';
    } catch (_) {
      return yyyyMm;
    }
  }

  static int _isoWeekNumber(DateTime date) {
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final wday = date.weekday; // Mon=1..Sun=7
    return ((dayOfYear - wday + 10) / 7).floor();
  }

  // ── Health section ──

  Widget _buildHealth() {
    return _SectionCard(
      title: 'Zdravje',
      icon: Icons.favorite,
      iconColor: kAccentGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mini line chart
          if (_weeklyHealthScores.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Tedensko povprečje zdravja',
                style: TextStyle(fontSize: 12, color: kTextSecondary)),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: _HealthLineChart(data: _weeklyHealthScores),
            ),
            const SizedBox(height: 4),
            // Week labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final e in _weeklyHealthScores)
                  Text(e.key.split('-').last,
                      style: const TextStyle(fontSize: 10, color: kTextMuted)),
              ],
            ),
          ],
          // Food group breakdown
          if (_foodGroupCounts.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Skupine zivil',
                style: TextStyle(fontSize: 12, color: kTextSecondary)),
            const SizedBox(height: 8),
            _buildFoodGroupBreakdown(),
          ],
          // Suggestion
          if (_healthSuggestion.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kAccentGreen.withAlpha(12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: kAccentGreen.withAlpha(40), width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates,
                      size: 15, color: kAccentGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_healthSuggestion,
                        style: const TextStyle(
                            fontSize: 12, color: kTextSecondary)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFoodGroupBreakdown() {
    // Sort by count descending, skip groups with 0
    final entries = _foodGroupCounts.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCount = entries.isNotEmpty ? entries.first.value : 1;

    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(foodGroupColors[e.key] ?? 0xFF64748b),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    foodGroupLabels[e.key] ?? e.key,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: kTextPrimary),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: _GlassProgressBar(
                    value: e.value / maxCount,
                    color: Color(foodGroupColors[e.key] ?? 0xFF64748b),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  child: Text('${e.value}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: kTextSecondary)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Section card ──

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  iconColor.withAlpha(0),
                  iconColor.withAlpha(80),
                  iconColor.withAlpha(0),
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ── Mini stat ──

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40), width: 0.5),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
                shadows: [
                  Shadow(color: color.withAlpha(100), blurRadius: 8),
                ],
              )),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: kTextMuted)),
        ],
      ),
    );
  }
}

// ── Menu type row ──

class _MenuTypeRow extends StatelessWidget {
  final String name;
  final int count;
  final int total;
  final int maxCount;
  final Color color;

  const _MenuTypeRow({
    required this.name,
    required this.count,
    required this.total,
    required this.maxCount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count / total * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: kTextPrimary)),
              ),
              Text('$count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                    shadows: [
                      Shadow(color: color.withAlpha(100), blurRadius: 6),
                    ],
                  )),
              const SizedBox(width: 6),
              SizedBox(
                width: 40,
                child: Text('${pct.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12, color: kTextMuted),
                    textAlign: TextAlign.right),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _GlassProgressBar(
            value: maxCount > 0 ? count / maxCount : 0,
            color: color,
          ),
        ],
      ),
    );
  }
}

// ── Keyword row ──

class _KeywordRow extends StatelessWidget {
  final int rank;
  final String keyword;
  final double score;

  const _KeywordRow({
    required this.rank,
    required this.keyword,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).toStringAsFixed(0);
    final glowColor =
        score >= 0.5 ? kAccentGreen : (score >= 0.3 ? kAccentAmber : kAccentRed);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('$rank.',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTextMuted)),
          ),
          Expanded(
            child: Text(keyword,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: kTextPrimary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: glowColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: glowColor.withAlpha(50), width: 0.5),
            ),
            child: Text('$pct%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: glowColor,
                  shadows: [
                    Shadow(color: glowColor.withAlpha(120), blurRadius: 6),
                  ],
                )),
          ),
        ],
      ),
    );
  }
}

// ── Month row ──

class _MonthRow extends StatelessWidget {
  final String label;
  final int count;
  final int maxCount;

  const _MonthRow({
    required this.label,
    required this.count,
    required this.maxCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: kTextSecondary)),
          ),
          Expanded(
            child: _GlassProgressBar(
              value: maxCount > 0 ? count / maxCount : 0,
              color: kAccentBlue,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kTextPrimary),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

// ── Glass progress bar ──

class _GlassProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const _GlassProgressBar({
    required this.value,
    required this.color,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: kGlassFill,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: kGlassBorder, width: 0.5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(80),
                blurRadius: 6,
                spreadRadius: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Health mini line chart ──

class _HealthLineChart extends StatelessWidget {
  final List<MapEntry<String, double>> data;

  const _HealthLineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 100),
      painter: _LineChartPainter(data),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<MapEntry<String, double>> data;

  _LineChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const minY = 1.0;
    const maxY = 10.0;
    const padTop = 16.0;
    const padBottom = 4.0;
    final chartHeight = size.height - padTop - padBottom;

    double yOf(double v) {
      final normalized = (v - minY) / (maxY - minY);
      return padTop + chartHeight * (1 - normalized);
    }

    // Draw horizontal guide lines at 3, 5, 7
    final guidePaint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..strokeWidth = 0.5;
    for (final g in [3.0, 5.0, 7.0]) {
      final gy = yOf(g);
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), guidePaint);
    }

    // Y‑axis labels
    final labelStyle = TextStyle(
      color: kTextMuted.withAlpha(150),
      fontSize: 9,
    );
    for (final g in [3, 5, 7, 10]) {
      final tp = TextPainter(
        text: TextSpan(text: '$g', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, yOf(g.toDouble()) - tp.height / 2));
    }

    if (data.length == 1) {
      // Single point: just draw a dot
      final y = yOf(data.first.value);
      final color = _dotColor(data.first.value);
      canvas.drawCircle(
        Offset(size.width / 2, y),
        5,
        Paint()..color = color,
      );
      return;
    }

    // Build points
    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = yOf(data[i].value);
      points.add(Offset(x, y));
    }

    // Gradient fill under line
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          kAccentGreen.withAlpha(40),
          kAccentGreen.withAlpha(0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePaint = Paint()
      ..color = kAccentGreen
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, linePaint);

    // Glow line
    final glowPaint = Paint()
      ..color = kAccentGreen.withAlpha(40)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(linePath, glowPaint);

    // Dots
    for (var i = 0; i < points.length; i++) {
      final color = _dotColor(data[i].value);
      // Outer glow
      canvas.drawCircle(
        points[i],
        6,
        Paint()
          ..color = color.withAlpha(30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      // Dot
      canvas.drawCircle(points[i], 4, Paint()..color = color);
      // Inner highlight
      canvas.drawCircle(
          points[i], 2, Paint()..color = Colors.white.withAlpha(60));

      // Score label above dot
      final tp = TextPainter(
        text: TextSpan(
          text: data[i].value.toStringAsFixed(1),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas, Offset(points[i].dx - tp.width / 2, points[i].dy - 14));
    }
  }

  Color _dotColor(double value) {
    if (value >= 7) return kAccentGreen;
    if (value >= 4) return kAccentYellow;
    return kAccentRed;
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.data != data;
}

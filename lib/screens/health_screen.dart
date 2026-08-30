import 'package:flutter/material.dart';

import '../models/meal_option.dart';
import '../services/credentials_store.dart';
import '../services/easistent_client.dart';
import '../services/health_scorer.dart';
import '../theme.dart';
import '../util/dates.dart';

/// Bottom gutter. The tab bar insets content on its own now, so this is
/// just breathing room at the end of a scroll.
const _navBarPad = 104.0;

/// Color for a health score 1–10.
Color healthColor(int score) {
  if (score >= 7) return kAccentGreen;
  if (score >= 4) return kAccentYellow;
  return kAccentRed;
}

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  bool _isLoading = true;
  String? _error;

  EAsistentClient? _client;
  int? _currentWeek;
  Map<String, List<MealOption>> _menu = {};

  /// menuId → health score (1–10)
  final Map<String, int> _healthScores = {};

  /// date → [1st, 2nd, 3rd] menuIds sorted by health score descending
  final Map<String, List<String>> _topThree = {};

  /// date → menuId of currently ordered option (if any)
  final Map<String, String> _orderedPicks = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? week}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Login once, reuse client for navigation
      if (_client == null) {
        final creds = await CredentialsStore.load();
        if (creds == null) {
          setState(() {
            _error = 'Ni shranjenih podatkov za prijavo.';
            _isLoading = false;
          });
          return;
        }
        _client =
            EAsistentClient(username: creds.username, password: creds.password);
        await _client!.login();
      }

      Future<Map<String, List<MealOption>>> fetchMenu() async {
        if (week != null) {
          final m = await _client!.getWeeklyMenu(week: week);
          _currentWeek = week;
          return m;
        } else {
          final html = await _client!.getMealPage();
          _currentWeek = _client!.findCurrentWeek(html);
          return _client!.parseMealTable(html);
        }
      }

      Map<String, List<MealOption>> menu;
      try {
        menu = await fetchMenu();
      } catch (_) {
        // Session likely stale — re-login and retry once
        await _client!.relogin();
        menu = await fetchMenu();
      }

      _menu = menu;
      _healthScores.clear();
      _topThree.clear();
      _orderedPicks.clear();

      for (final entry in menu.entries) {
        final date = entry.key;
        final options = entry.value;

        for (final opt in options) {
          final hs = scoreMeal(opt.description).score;
          _healthScores[opt.menuId] = hs;

          if (opt.status == 'ordered') {
            _orderedPicks[date] = opt.menuId;
          }
        }

        // Top 3 by health score
        final ranked = options.toList()
          ..sort((a, b) =>
              (_healthScores[b.menuId] ?? 0)
                  .compareTo(_healthScores[a.menuId] ?? 0));
        _topThree[date] = ranked.take(3).map((o) => o.menuId).toList();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // ── Weekly summary stats ──

  double get _currentPicksAvg {
    if (_orderedPicks.isEmpty) return 0;
    var sum = 0;
    var count = 0;
    for (final entry in _orderedPicks.entries) {
      final s = _healthScores[entry.value];
      if (s != null) {
        sum += s;
        count++;
      }
    }
    return count > 0 ? sum / count : 0;
  }

  double get _healthiestPicksAvg {
    if (_topThree.isEmpty) return 0;
    var sum = 0;
    var count = 0;
    for (final entry in _topThree.entries) {
      if (entry.value.isNotEmpty) {
        final s = _healthScores[entry.value.first];
        if (s != null) {
          sum += s;
          count++;
        }
      }
    }
    return count > 0 ? sum / count : 0;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Zdravje'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Prejšnji teden',
            onPressed: _currentWeek != null && !_isLoading
                ? () => _load(week: _currentWeek! - 1)
                : null,
          ),
          Center(
            child: GlassCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              radius: 10,
              child: Text('T${_currentWeek ?? '?'}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Naslednji teden',
            onPressed: _currentWeek != null && !_isLoading
                ? () => _load(week: _currentWeek! + 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Osveži',
            onPressed: _isLoading ? null : () => _load(week: _currentWeek),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _menu.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding:
                            const EdgeInsets.fromLTRB(12, 8, 12, _navBarPad),
                        children: [
                          _buildWeeklySummary(),
                          const SizedBox(height: 14),
                          ..._buildDays(),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: kAccentRed),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: kAccentRed),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _load,
              child: const Text('Poskusi znova'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 56, color: kTextMuted),
          SizedBox(height: 16),
          Text('Ni podatkov',
              style: TextStyle(fontSize: 18, color: kTextMuted)),
          SizedBox(height: 8),
          Text('Prijavi se v zavihku Meni',
              style: TextStyle(fontSize: 13, color: kTextMuted)),
        ],
      ),
    );
  }

  // ── Weekly summary card ──

  Widget _buildWeeklySummary() {
    final currentAvg = _currentPicksAvg;
    final bestAvg = _healthiestPicksAvg;
    final hasOrders = _orderedPicks.isNotEmpty;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Muted uppercase header, no icon and no gradient rule — matches
          // Nastavitve and Statistika.
          Text('TEDENSKI PREGLED',
              style: kFootnote.copyWith(letterSpacing: 0.5)),
          const SizedBox(height: kSp12),
          Row(
            children: [
              Expanded(
                child: _SummaryBox(
                  label: hasOrders ? 'Tvoje izbire' : 'Ni izbir',
                  value: hasOrders ? currentAvg.toStringAsFixed(1) : '–',
                  subLabel: '/10',
                  color: hasOrders ? healthColor(currentAvg.round()) : kTextMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryBox(
                  label: 'Najzdravejše',
                  value: bestAvg.toStringAsFixed(1),
                  subLabel: '/10',
                  color: healthColor(bestAvg.round()),
                ),
              ),
            ],
          ),
          if (hasOrders && bestAvg > currentAvg + 0.5) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kAccentGreen.withAlpha(12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kAccentGreen.withAlpha(40), width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates,
                      size: 15, color: kAccentGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Z najzdravejšimi izbirami bi imel/a povprečje ${bestAvg.toStringAsFixed(1)} namesto ${currentAvg.toStringAsFixed(1)}.',
                      style: const TextStyle(fontSize: 12, color: kTextSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Day cards ──

  List<Widget> _buildDays() {
    final sortedDates = _menu.keys.toList()..sort();
    return [
      for (final date in sortedDates) _buildDayCard(date),
    ];
  }

  Widget _buildDayCard(String date) {
    final options = _menu[date]!;
    final dayLabel = formatDayDate(date);
    final top3 = _topThree[date] ?? [];
    final orderedId = _orderedPicks[date];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header
            Row(
              children: [
                Text(dayLabel,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary)),
                const Spacer(),
                if (orderedId != null)
                  PillChip(
                    label:
                        'Izbrano: ${(_healthScores[orderedId] ?? 0)}/10',
                    color: healthColor(_healthScores[orderedId] ?? 5),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Options
            for (var i = 0; i < options.length; i++)
              _buildOptionRow(options[i], top3, orderedId),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionRow(
      MealOption opt, List<String> top3, String? orderedId) {
    final hs = _healthScores[opt.menuId] ?? 5;
    final color = healthColor(hs);
    final rank = top3.indexOf(opt.menuId); // 0=gold, 1=silver, 2=bronze, -1=none
    final isOrdered = opt.menuId == orderedId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score circle
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(20),
              border: Border.all(color: color.withAlpha(80), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: color.withAlpha(40), blurRadius: 6, spreadRadius: 0),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '$hs',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        opt.menuName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isOrdered ? kAccentAmber : kTextPrimary,
                        ),
                      ),
                    ),
                    if (rank >= 0 && rank < 3)
                      _MedalBadge(rank: rank),
                    if (isOrdered) ...[
                      const SizedBox(width: 4),
                      const PillChip(label: 'Izbrano', color: kAccentAmber),
                    ],
                  ],
                ),
                if (opt.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    opt.description,
                    style: const TextStyle(fontSize: 11, color: kTextMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary box ──

class _SummaryBox extends StatelessWidget {
  final String label;
  final String value;
  final String subLabel;
  final Color color;

  const _SummaryBox({
    required this.label,
    required this.value,
    required this.subLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40), width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: color,
                  )),
              Text(subLabel,
                  style: TextStyle(fontSize: 13, color: color.withAlpha(150))),
            ],
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, color: kTextMuted)),
        ],
      ),
    );
  }
}

// ── Medal badge (gold / silver / bronze) ──

class _MedalBadge extends StatelessWidget {
  /// 0 = gold, 1 = silver, 2 = bronze
  final int rank;

  const _MedalBadge({required this.rank});

  static const _colors = [
    Color(0xFFFFD700), // gold
    Color(0xFFC0C0C0), // silver
    Color(0xFFCD7F32), // bronze
  ];
  static const _labels = ['1.', '2.', '3.'];

  @override
  Widget build(BuildContext context) {
    final color = _colors[rank];
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(30),
        border: Border.all(color: color.withAlpha(160), width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withAlpha(60), blurRadius: 6, spreadRadius: 0),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        _labels[rank],
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

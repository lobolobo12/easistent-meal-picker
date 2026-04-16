import 'dart:math';

import 'package:flutter/material.dart';

import '../services/meal_predictor.dart';
import '../services/preference_learner.dart';
import '../services/preferences_store.dart';
import '../services/rating_store.dart';
import '../services/training_store.dart';
import '../theme.dart';

String _stripAllergens(String desc) {
  return desc
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .trim()
      .replaceAll(RegExp(r',\s*$'), '');
}

const _navBarPad = 90.0;

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  bool _isLoading = true;
  String? _error;

  final Map<String, List<String>> _pool = {};
  List<String> _menuTypes = [];

  List<_QuizOption> _currentOptions = [];
  int _roundNumber = 0;
  int _sessionPicks = 0;
  int _totalPicks = 0;

  MealPredictor? _predictor;
  List<dynamic> _trainingData = [];
  Map<String, dynamic> _preferences = {};
  List<dynamic> _ratings = [];

  int? _pickedIndex;
  bool _isAnimating = false;

  final _random = Random();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      _trainingData = await TrainingStore.load();
      _preferences = await PreferencesStore.load();
      _ratings = await RatingStore.load();

      _buildPool();
      _rebuildPredictor();
      _totalPicks = _trainingData.length;
      _generateRound();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _buildPool() {
    _pool.clear();
    final seen = <String, Set<String>>{};
    for (final day in _trainingData) {
      for (final opt in (day as Map)['options'] as List) {
        final name = (opt as Map)['menu_name'] as String;
        final desc = (opt['description'] as String).trim();
        if (desc.isEmpty) continue;
        seen.putIfAbsent(name, () => {});
        if (seen[name]!.add(desc)) {
          _pool.putIfAbsent(name, () => []).add(desc);
        }
      }
    }
    _menuTypes = _pool.keys.toList()..sort();
  }

  void _rebuildPredictor() {
    _predictor = MealPredictor.fromData(
      trainingData: _trainingData,
      preferences: _preferences,
      ratings: _ratings,
    );
  }

  void _generateRound() {
    _roundNumber++;
    _pickedIndex = null;
    _isAnimating = false;
    _currentOptions = [
      for (final name in _menuTypes)
        if (_pool[name]!.isNotEmpty)
          _QuizOption(
              name, _pool[name]![_random.nextInt(_pool[name]!.length)]),
    ];
  }

  int? get _aiPickIndex {
    if (_predictor == null || _currentOptions.isEmpty) return null;
    int? bestIdx;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < _currentOptions.length; i++) {
      final opt = _currentOptions[i];
      final score = _predictor!.scoreOption(opt.menuName, opt.description);
      if (score > bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  Future<void> _onPick(int index) async {
    if (_isAnimating) return;

    setState(() {
      _pickedIndex = index;
      _isAnimating = true;
    });

    final roundData = <String, dynamic>{
      'date': 'quiz-${DateTime.now().millisecondsSinceEpoch}',
      'options': [
        for (var i = 0; i < _currentOptions.length; i++)
          {
            'menu_name': _currentOptions[i].menuName,
            'menu_id': 'quiz',
            'description': _currentOptions[i].description,
            'chosen': i == index,
          },
      ],
    };

    _trainingData.add(roundData);
    _sessionPicks++;
    _totalPicks++;

    await TrainingStore.save(_trainingData);
    _preferences = deriveAutoPreferences(
      trainingData: _trainingData,
      currentPrefs: _preferences,
    );
    await PreferencesStore.save(_preferences);
    _rebuildPredictor();

    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    setState(() => _generateRound());
  }

  void _skip() {
    if (_isAnimating) return;
    setState(() => _generateRound());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Trening'),
        actions: [
          if (!_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'Skupaj: $_totalPicks',
                  style: const TextStyle(fontSize: 13, color: kTextMuted),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: kAccentRed),
                      textAlign: TextAlign.center))
              : _buildQuiz(),
    );
  }

  Widget _buildQuiz() {
    final aiIdx = _aiPickIndex;

    return Column(
      children: [
        // Stats bar
        GlassBar(
          child: Row(
            children: [
              _StatChip(
                icon: Icons.flag_outlined,
                label: 'Runda $_roundNumber',
                color: kAccentBlue,
              ),
              const SizedBox(width: 12),
              _StatChip(
                icon: Icons.check_circle_outline,
                label: 'Ta seja: $_sessionPicks',
                color: kAccentGreen,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _isAnimating ? null : _skip,
                icon: const Icon(Icons.skip_next, size: 18, color: kTextMuted),
                label: const Text('Preskoči',
                    style: TextStyle(fontSize: 13, color: kTextMuted)),
              ),
            ],
          ),
        ),

        // Prompt
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Izberi najboljšo malico:',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary),
            ),
          ),
        ),

        // Options
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, _navBarPad),
            itemCount: _currentOptions.length,
            itemBuilder: (context, index) {
              final opt = _currentOptions[index];
              final isPicked = _pickedIndex == index;
              final isAiPick = aiIdx == index;

              return _QuizCard(
                index: index,
                menuName: opt.menuName,
                description: _stripAllergens(opt.description),
                isPicked: isPicked,
                isAiPick: isAiPick,
                enabled: !_isAnimating,
                onTap: () => _onPick(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Stat chip ──

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Quiz option card ──

class _QuizCard extends StatelessWidget {
  final int index;
  final String menuName;
  final String description;
  final bool isPicked;
  final bool isAiPick;
  final bool enabled;
  final VoidCallback onTap;

  const _QuizCard({
    required this.index,
    required this.menuName,
    required this.description,
    required this.isPicked,
    required this.isAiPick,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = menuColor(menuName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: AnimatedScale(
        scale: isPicked ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: GlassCard(
          selected: isPicked,
          borderColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          onTap: enabled ? onTap : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: isPicked
                        ? Icon(Icons.check_circle,
                            key: const ValueKey('check'),
                            size: 22,
                            color: accent)
                        : Container(
                            key: const ValueKey('num'),
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: kTextMuted, width: 1.5),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: kTextMuted,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  if (isAiPick) ...[
                    Icon(Icons.auto_awesome,
                        size: 14, color: kAccentMauve.withAlpha(200)),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      menuName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isPicked ? accent : kTextPrimary,
                      ),
                    ),
                  ),
                  if (isAiPick)
                    Text('AI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: kAccentMauve,
                          shadows: [
                            Shadow(
                                color: kAccentMauve.withAlpha(120),
                                blurRadius: 8),
                          ],
                        )),
                ],
              ),
              // Description
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: kTextSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizOption {
  final String menuName;
  final String description;
  const _QuizOption(this.menuName, this.description);
}

import 'dart:math';

import 'package:flutter/material.dart';

import '../services/credentials_store.dart';
import '../services/easistent_client.dart';
import '../services/meal_predictor.dart';
import '../services/meal_structure_store.dart';
import '../services/onboarding_store.dart';
import '../services/preference_learner.dart';
import '../services/preferences_store.dart';
import '../services/scheduler_service.dart';
import '../services/training_store.dart';
import '../theme.dart';

enum _Step { welcome, login, aiQuestion, scraping, quiz, done }

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step _step = _Step.welcome;

  // Login
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loggingIn = false;
  String? _loginError;
  EAsistentClient? _client;

  // Scraping
  double _scrapeProgress = 0;
  String _scrapeStatus = '';
  int _scrapedDays = 0;

  // Quiz
  final _random = Random();
  final Map<String, List<String>> _pool = {};
  List<String> _menuTypes = [];
  List<_QuizOption> _currentOptions = [];
  int _quizRound = 0;
  static const _maxQuizRounds = 20;
  int? _pickedIndex;
  bool _isAnimating = false;
  MealPredictor? _predictor;
  List<dynamic> _trainingData = [];
  Map<String, dynamic> _preferences = {};

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── Login ──

  Future<void> _doLogin() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) return;

    setState(() {
      _loggingIn = true;
      _loginError = null;
    });

    try {
      _client = EAsistentClient(username: user, password: pass);
      await _client!.login();
      await CredentialsStore.save(user, pass);
      await requestNotificationPermission();
      await scheduleWeeklyTasks();
      if (!mounted) return;
      setState(() {
        _loggingIn = false;
        _step = _Step.aiQuestion;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loginError = e.toString().replaceFirst('Exception: ', '');
        _loggingIn = false;
      });
    }
  }

  // ── Scraping ──

  Future<void> _startScraping() async {
    setState(() => _step = _Step.scraping);

    try {
      final html = await _client!.getMealPage();
      final currentWeek = _client!.findCurrentWeek(html);
      if (currentWeek == null) {
        _finishScraping();
        return;
      }

      // Detect structure from current week
      final currentMenu = _client!.parseMealTable(html);
      MealStructureStore.detectAndSave(currentMenu);

      const weeksToScrape = 20;
      final startWeek =
          (currentWeek - weeksToScrape + 1).clamp(1, currentWeek);
      final totalWeeks = currentWeek - startWeek + 1;
      var fetched = 0;

      _trainingData = await TrainingStore.load();
      final existingDates = <String>{
        for (final d in _trainingData)
          if (d is Map && d['date'] is String) d['date'] as String,
      };

      for (var w = currentWeek; w >= startWeek; w--) {
        if (!mounted) return;
        fetched++;
        setState(() {
          _scrapeProgress = fetched / totalWeeks;
          _scrapeStatus = 'Teden $w ($fetched/$totalWeeks)';
        });

        try {
          final menu = await _client!.getWeeklyMenu(week: w);
          if (menu.isEmpty) continue;

          for (final entry in menu.entries) {
            final date = entry.key;
            if (existingDates.contains(date)) continue;
            final options = entry.value;
            final orderedOpt =
                options.where((o) => o.status == 'ordered').firstOrNull;
            if (orderedOpt == null) continue;
            if (options.every((o) => o.description.trim().isEmpty)) continue;

            _trainingData.add({
              'date': date,
              'options': [
                for (final o in options)
                  {
                    'menu_name': o.menuName,
                    'menu_id': o.menuId,
                    'description': o.description,
                    'chosen': o.menuId == orderedOpt.menuId,
                  },
              ],
            });
            existingDates.add(date);
            _scrapedDays++;
          }
        } catch (_) {
          // Skip problematic weeks
        }
      }

      await TrainingStore.save(_trainingData);
      _preferences = await PreferencesStore.load();
      _preferences = deriveAutoPreferences(
        trainingData: _trainingData,
        currentPrefs: _preferences,
      );
      await PreferencesStore.save(_preferences);

      if (!mounted) return;
      _finishScraping();
    } catch (_) {
      if (!mounted) return;
      _finishScraping();
    }
  }

  void _finishScraping() {
    _buildPool();
    if (_pool.isNotEmpty && _menuTypes.length >= 2) {
      _predictor = MealPredictor.fromData(
        trainingData: _trainingData,
        preferences: _preferences,
      );
      _generateRound();
      setState(() => _step = _Step.quiz);
    } else {
      _finishOnboarding();
    }
  }

  // ── Quiz ──

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

  void _generateRound() {
    _quizRound++;
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

  Future<void> _onQuizPick(int index) async {
    if (_isAnimating) return;

    setState(() {
      _pickedIndex = index;
      _isAnimating = true;
    });

    _trainingData.add({
      'date': 'quiz-onboard-${DateTime.now().millisecondsSinceEpoch}',
      'options': [
        for (var i = 0; i < _currentOptions.length; i++)
          {
            'menu_name': _currentOptions[i].menuName,
            'menu_id': 'quiz',
            'description': _currentOptions[i].description,
            'chosen': i == index,
          },
      ],
    });

    await TrainingStore.save(_trainingData);
    _preferences = deriveAutoPreferences(
      trainingData: _trainingData,
      currentPrefs: _preferences,
    );
    await PreferencesStore.save(_preferences);
    _predictor = MealPredictor.fromData(
      trainingData: _trainingData,
      preferences: _preferences,
    );

    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    if (_quizRound >= _maxQuizRounds) {
      _finishOnboarding();
    } else {
      setState(() => _generateRound());
    }
  }

  // ── Finish ──

  Future<void> _finishOnboarding() async {
    await OnboardingStore.markComplete();
    if (mounted) setState(() => _step = _Step.done);
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: kBgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: switch (_step) {
              _Step.welcome => _buildWelcome(),
              _Step.login => _buildLogin(),
              _Step.aiQuestion => _buildAiQuestion(),
              _Step.scraping => _buildScraping(),
              _Step.quiz => _buildQuiz(),
              _Step.done => _buildDone(),
            },
          ),
        ),
      ),
    );
  }

  // ── Welcome ──

  Widget _buildWelcome() {
    return Center(
      key: const ValueKey('welcome'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_menu, size: 72, color: kAccentAmber),
            const SizedBox(height: 16),
            const Text('eAsistent Meal Picker',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimary)),
            const SizedBox(height: 12),
            const Text(
              'Pametno izbira malice na eAsistent.\n'
              'AI se uči tvojih preferenc in samodejno oddaja izbire.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: kTextSecondary),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 200,
              height: 48,
              child: FilledButton(
                onPressed: () => setState(() => _step = _Step.login),
                child:
                    const Text('Začni', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Login ──

  Widget _buildLogin() {
    return Center(
      key: const ValueKey('login'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.login, size: 48, color: kAccentAmber),
                const SizedBox(height: 8),
                const Text('Prijava v eAsistent',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary)),
                const SizedBox(height: 24),
                TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Uporabniško ime',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Geslo',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _doLogin(),
                ),
                if (_loginError != null) ...[
                  const SizedBox(height: 14),
                  Text(_loginError!,
                      style: const TextStyle(color: kAccentRed),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loggingIn ? null : _doLogin,
                    child: _loggingIn
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Prijava',
                            style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── AI Question ──

  Widget _buildAiQuestion() {
    return Center(
      key: const ValueKey('ai'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome,
                    size: 48, color: kAccentMauve),
                const SizedBox(height: 12),
                const Text('Želim nastaviti AI?',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary)),
                const SizedBox(height: 12),
                const Text(
                  'Lahko pregledam tvojo preteklo zgodovino naročil '
                  'in se naučim tvojih preferenc. Potem te še prosim '
                  'za kratek kviz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: kTextSecondary),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _startScraping,
                    child: const Text('Da, nastavi zdaj',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _finishOnboarding,
                    child: const Text('Preskoči',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Scraping ──

  Widget _buildScraping() {
    return Center(
      key: const ValueKey('scraping'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history, size: 48, color: kAccentBlue),
                const SizedBox(height: 12),
                const Text('Nalagam zgodovino...',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary)),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _scrapeProgress,
                    minHeight: 8,
                    backgroundColor: kGlassFill,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(kAccentBlue),
                  ),
                ),
                const SizedBox(height: 12),
                Text(_scrapeStatus,
                    style:
                        const TextStyle(fontSize: 13, color: kTextMuted)),
                const SizedBox(height: 4),
                Text('$_scrapedDays dni z naročili',
                    style: const TextStyle(
                        fontSize: 14,
                        color: kAccentGreen,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                const Text(
                  'To lahko traja minuto ali dve...',
                  style: TextStyle(
                      fontSize: 12,
                      color: kTextMuted,
                      fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Quiz ──

  String _stripAllergens(String desc) {
    return desc
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .trim()
        .replaceAll(RegExp(r',\s*$'), '');
  }

  Widget _buildQuiz() {
    final aiIdx = _aiPickIndex;

    return Column(
      key: const ValueKey('quiz'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              const Icon(Icons.fitness_center,
                  size: 20, color: kAccentMauve),
              const SizedBox(width: 8),
              Text('Runda $_quizRound / $_maxQuizRounds',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary)),
              const Spacer(),
              OutlinedButton(
                onPressed: _isAnimating ? null : _finishOnboarding,
                child: const Text('Končaj'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _quizRound / _maxQuizRounds,
              minHeight: 4,
              backgroundColor: kGlassFill,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(kAccentMauve),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Izberi najboljšo malico:',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: kTextSecondary),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            itemCount: _currentOptions.length,
            itemBuilder: (context, index) {
              final opt = _currentOptions[index];
              final isPicked = _pickedIndex == index;
              final isAiPick = aiIdx == index;
              final accent = menuColor(opt.menuName);

              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: GlassCard(
                  selected: isPicked,
                  borderColor: accent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  onTap:
                      _isAnimating ? null : () => _onQuizPick(index),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedSwitcher(
                            duration:
                                const Duration(milliseconds: 200),
                            child: isPicked
                                ? Icon(Icons.check_circle,
                                    key: const ValueKey('c'),
                                    size: 20,
                                    color: accent)
                                : const Icon(Icons.radio_button_off,
                                    key: ValueKey('r'),
                                    size: 20,
                                    color: kTextMuted),
                          ),
                          const SizedBox(width: 8),
                          if (isAiPick) ...[
                            Icon(Icons.auto_awesome,
                                size: 13,
                                color: kAccentMauve.withAlpha(200)),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              opt.menuName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color:
                                    isPicked ? accent : kTextPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (opt.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.only(left: 28),
                          child: Text(
                            _stripAllergens(opt.description),
                            style: const TextStyle(
                                fontSize: 12,
                                color: kTextSecondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Done ──

  Widget _buildDone() {
    return Center(
      key: const ValueKey('done'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 72, color: kAccentGreen),
            const SizedBox(height: 16),
            const Text('Vse pripravljeno!',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimary)),
            const SizedBox(height: 12),
            if (_scrapedDays > 0 || _quizRound > 0)
              Text(
                [
                  if (_scrapedDays > 0) '$_scrapedDays dni zgodovine',
                  if (_quizRound > 0) '$_quizRound kviz odgovorov',
                ].join(' + '),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 14, color: kTextSecondary),
              ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 48,
              child: FilledButton(
                onPressed: widget.onComplete,
                child: const Text('Odpri aplikacijo',
                    style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
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

import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/meal_option.dart';
import '../services/absence_store.dart';
import '../services/credentials_store.dart';
import '../services/easistent_client.dart';
import '../services/meal_predictor.dart';
import '../services/meal_structure_store.dart';
import '../services/preference_learner.dart';
import '../services/preferences_store.dart';
import '../services/rating_store.dart';
import '../services/scheduler_service.dart';
import '../services/submission_log.dart';
import '../services/training_store.dart';
import '../services/health_scorer.dart';
import '../services/widget_service.dart';
import '../theme.dart';

const _dayNames = <int, String>{
  1: 'Ponedeljek',
  2: 'Torek',
  3: 'Sreda',
  4: 'Četrtek',
  5: 'Petek',
  6: 'Sobota',
  7: 'Nedelja',
};

/// Sentinel value in _selections meaning "cancel meal for this day".
const _cancelId = '__odjava__';

/// Bottom padding so content doesn't hide behind floating nav bar.
const _navBarPad = 90.0;

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => MenuScreenState();
}

class MenuScreenState extends State<MenuScreen> {
  // Login
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _autoLoginAttempted = false;
  String? _error;

  // Client & predictor
  EAsistentClient? _client;
  MealPredictor? _predictor;

  // Menu data
  Map<String, List<MealOption>> _menu = {};
  int? _currentWeek;

  // Selections: date -> menuId
  final Map<String, String> _aiPicks = {};
  final Map<String, String> _selections = {};
  // Scores: "date|menuId" -> score
  final Map<String, double> _scores = {};

  // Lock probing
  final Set<String> _partiallyLockedDates = {};
  bool _isProbing = false;
  int _probeGeneration = 0;

  // Submission
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Auto-login ──

  Future<void> _tryAutoLogin() async {
    final creds = await CredentialsStore.load();
    if (creds == null) {
      setState(() => _autoLoginAttempted = true);
      return;
    }
    _usernameCtrl.text = creds.username;
    _passwordCtrl.text = creds.password;
    setState(() {
      _isLoading = true;
      _autoLoginAttempted = true;
    });
    await _loginWith(creds.username, creds.password);
  }

  /// Called from Nastavitve tab via GlobalKey.
  void logout() {
    CredentialsStore.clear();
    cancelScheduledTasks();
    setState(() {
      _isLoggedIn = false;
      _isLoading = false;
      _error = null;
      _client = null;
      _predictor = null;
      _menu = {};
      _currentWeek = null;
      _aiPicks.clear();
      _selections.clear();
      _scores.clear();
      _partiallyLockedDates.clear();
      _probeGeneration++;
      _usernameCtrl.clear();
      _passwordCtrl.clear();
    });
  }

  // ── Login ──

  Future<void> _login() async {
    final user = _usernameCtrl.text.trim();
    final pass = _passwordCtrl.text;
    if (user.isEmpty || pass.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    await _loginWith(user, pass);
  }

  Future<void> _loginWith(String user, String pass) async {
    try {
      _client = EAsistentClient(username: user, password: pass);
      await _client!.login();
      _isLoggedIn = true;

      await CredentialsStore.save(user, pass);
      await requestNotificationPermission();
      await scheduleWeeklyTasks();

      await Future.wait([_loadPredictor(), _fetchMenuInternal()]);
      _computePicks();
      _updateWidget();
      MealStructureStore.detectAndSave(_menu);
      setState(() => _isLoading = false);
      _probeLockedDays();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPredictor() async {
    final results = await Future.wait([
      TrainingStore.load(),
      PreferencesStore.load(),
      RatingStore.load(),
    ]);
    _predictor = MealPredictor.fromData(
      trainingData: results[0] as List<dynamic>,
      preferences: results[1] as Map<String, dynamic>,
      ratings: results[2] as List<dynamic>,
    );
  }

  // ── Menu fetching ──

  Future<void> _fetchMenuInternal({int? week}) async {
    if (week != null) {
      _menu = await _client!.getWeeklyMenu(week: week);
      _currentWeek = week;
    } else {
      final html = await _client!.getMealPage();
      _currentWeek = _client!.findCurrentWeek(html);
      _menu = _client!.parseMealTable(html);
    }
  }

  /// Try an async operation; on failure, re-login once and retry.
  Future<void> _withRelogin(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      await _client!.relogin();
      await action();
    }
  }

  Future<void> _fetchMenu({int? week}) async {
    _probeGeneration++;
    setState(() {
      _isLoading = true;
      _error = null;
      _partiallyLockedDates.clear();
      _isProbing = false;
    });
    try {
      await Future.wait([
        _loadPredictor(),
        _withRelogin(() => _fetchMenuInternal(week: week)),
      ]);
      _computePicks();
      _updateWidget();
      MealStructureStore.detectAndSave(_menu);
      setState(() => _isLoading = false);
      _probeLockedDays();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // ── Predictor ──

  void _computePicks() {
    _aiPicks.clear();
    _selections.clear();
    _scores.clear();

    for (final entry in _menu.entries) {
      final date = entry.key;
      final options = entry.value;

      if (_predictor != null) {
        final dayScores = _predictor!.scoreDay(options);
        for (final s in dayScores.entries) {
          _scores['$date|${s.key}'] = s.value;
        }

        String? bestId;
        var bestScore = double.negativeInfinity;
        for (final opt in options) {
          if (opt.status != 'available' && opt.status != 'ordered') continue;
          final score = _predictor!.scoreOption(opt.menuName, opt.description);
          if (score > bestScore) {
            bestScore = score;
            bestId = opt.menuId;
          }
        }
        if (bestId != null) _aiPicks[date] = bestId;
      }

      final orderedOpt =
          options.where((o) => o.status == 'ordered').firstOrNull;
      if (orderedOpt != null) {
        _selections[date] = orderedOpt.menuId;
      } else if (_aiPicks.containsKey(date)) {
        _selections[date] = _aiPicks[date]!;
      }
    }
  }

  void _updateWidget() {
    updateHomeWidget(
      menu: _menu,
      predictor: _predictor,
      selections: _selections,
    );
  }

  double _getScore(String date, String menuId) =>
      _scores['$date|$menuId'] ?? 0.0;

  bool _isDaySelectable(String date) {
    final options = _menu[date];
    if (options == null) return false;
    return options
        .any((o) => o.status == 'available' || o.status == 'ordered');
  }

  // ── Lock probing ──

  Future<void> _probeLockedDays() async {
    if (_client == null || _menu.isEmpty) return;

    final gen = ++_probeGeneration;
    _partiallyLockedDates.clear();
    setState(() => _isProbing = true);

    final sortedDates = _menu.keys.toList()..sort();

    for (final date in sortedDates) {
      if (gen != _probeGeneration) break;

      final options = _menu[date]!;
      if (options.length < 2) continue;

      final orderedOpt =
          options.where((o) => o.status == 'ordered').firstOrNull;

      MealOption? probeOpt;
      for (var i = options.length - 1; i >= 0; i--) {
        if (options[i].menuId != orderedOpt?.menuId) {
          probeOpt = options[i];
          break;
        }
      }
      if (probeOpt == null) continue;

      try {
        await _client!.selectMeal(
          date: date,
          menuId: probeOpt.menuId,
          locationId: probeOpt.locationId,
          mealType: probeOpt.mealType,
        );

        await Future.delayed(const Duration(milliseconds: 300));

        if (orderedOpt != null) {
          try {
            await _client!.selectMeal(
              date: date,
              menuId: orderedOpt.menuId,
              locationId: orderedOpt.locationId,
              mealType: orderedOpt.mealType,
            );
          } catch (_) {
            if (mounted && gen == _probeGeneration) {
              showCenteredToast(context,
                  'Napaka: ni uspelo povrniti $date na ${orderedOpt.menuName}',
                  color: kAccentRed);
            }
          }
        } else {
          try {
            await _client!.cancelMeal(
              date: date,
              menuId: probeOpt.menuId,
              locationId: probeOpt.locationId,
              mealType: probeOpt.mealType,
            );
          } catch (_) {
            if (mounted && gen == _probeGeneration) {
              showCenteredToast(context,
                  'Napaka: ni uspelo preklicati preizkusa za $date',
                  color: kAccentRed);
            }
          }
        }
      } catch (_) {
        _partiallyLockedDates.add(date);
      }

      if (gen == _probeGeneration) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    if (mounted && gen == _probeGeneration) {
      setState(() => _isProbing = false);
    }
  }

  Future<void> _onOptionTap(String date, MealOption option) async {
    if (option.status != 'available' && option.status != 'ordered') return;
    if (!_isDaySelectable(date)) return;
    if (_partiallyLockedDates.contains(date)) {
      final options = _menu[date]!;
      if (options.isNotEmpty && option.menuId != options.first.menuId) return;

      // Toggle: if already selected, revert to ordered option or AI pick
      if (_selections[date] == option.menuId) {
        final orderedOpt =
            options.where((o) => o.status == 'ordered').firstOrNull;
        if (orderedOpt != null && orderedOpt.menuId != option.menuId) {
          setState(() => _selections[date] = orderedOpt.menuId);
        } else if (_aiPicks.containsKey(date) &&
            _aiPicks[date] != option.menuId) {
          setState(() => _selections[date] = _aiPicks[date]!);
        }
        return;
      }
    }
    setState(() => _selections[date] = option.menuId);
  }

  Future<void> _onCancelTap(String date) async {
    if (!_isDaySelectable(date)) return;

    // Toggle: if already cancelled, revert to ordered option or AI pick
    if (_selections[date] == _cancelId) {
      final options = _menu[date]!;
      final orderedOpt =
          options.where((o) => o.status == 'ordered').firstOrNull;
      if (orderedOpt != null) {
        setState(() => _selections[date] = orderedOpt.menuId);
      } else if (_aiPicks.containsKey(date)) {
        setState(() => _selections[date] = _aiPicks[date]!);
      }
      return;
    }

    setState(() => _selections[date] = _cancelId);
  }

  // ── Submission ──

  List<MapEntry<String, String>> get _submittableSelections {
    return _selections.entries.where((e) {
      if (!_isDaySelectable(e.key)) return false;
      final options = _menu[e.key]!;
      final orderedOpt =
          options.where((o) => o.status == 'ordered').firstOrNull;

      if (e.value == _cancelId) {
        return orderedOpt != null;
      }
      if (orderedOpt != null) return e.value != orderedOpt.menuId;
      return true;
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  Future<void> _confirmAndSubmit() async {
    final toSubmit = _submittableSelections;
    if (toSubmit.isEmpty) return;

    // Warn about irreversible locked-day changes before proceeding
    final lockedChanges =
        toSubmit.where((e) => _partiallyLockedDates.contains(e.key)).toList();

    if (lockedChanges.isNotEmpty) {
      final lockedLines = lockedChanges.map((e) {
        final options = _menu[e.key]!;
        if (e.value == _cancelId) {
          return '${_formatDateShort(e.key)}: Odjava';
        }
        final newOpt = options.firstWhere((o) => o.menuId == e.value);
        return '${_formatDateShort(e.key)}: ${newOpt.menuName}';
      }).toList();

      final lockedConfirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pozor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Pozor: na teh dnevih ne mores vec zamenjati nazaj:'),
              const SizedBox(height: 8),
              for (final line in lockedLines) Text('• $line'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Prekliči'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: kAccentYellow),
              child: const Text('Oddaj'),
            ),
          ],
        ),
      );

      if (lockedConfirmed != true) return;
    }

    if (!mounted) return;

    final lines = toSubmit.map((e) {
      final options = _menu[e.key]!;
      final orderedOpt =
          options.where((o) => o.status == 'ordered').firstOrNull;

      if (e.value == _cancelId) {
        return '${_formatDateShort(e.key)}: Odjava (${orderedOpt?.menuName ?? '?'})';
      }
      final newOpt = options.firstWhere((o) => o.menuId == e.value);
      if (orderedOpt != null) {
        return '${_formatDateShort(e.key)}: ${orderedOpt.menuName} -> ${newOpt.menuName}';
      }
      return '${_formatDateShort(e.key)}: ${newOpt.menuName}';
    }).toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oddaj izbire?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final line in lines) Text('• $line')],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Prekliči'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oddaj'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    var successCount = 0;
    String? lastError;
    final successfulDays = <String>[];

    for (final entry in toSubmit) {
      final options = _menu[entry.key]!;
      final orderedOpt =
          options.where((o) => o.status == 'ordered').firstOrNull;
      try {
        if (entry.value == _cancelId) {
          if (orderedOpt != null) {
            await _client!.cancelMeal(
              date: entry.key,
              menuId: orderedOpt.menuId,
              locationId: orderedOpt.locationId,
              mealType: orderedOpt.mealType,
            );
            successCount++;
            await SubmissionLog.add({
              'date': entry.key,
              'menuName': 'Odjava',
              'menuId': _cancelId,
              'description': 'Odjava od ${orderedOpt.menuName}',
              'submittedAt': DateTime.now().toIso8601String(),
              'aiPickMenuName': _aiPicks.containsKey(entry.key)
                  ? options
                      .where((o) => o.menuId == _aiPicks[entry.key])
                      .firstOrNull
                      ?.menuName
                  : null,
            });
          }
        } else {
          final opt = options.firstWhere((o) => o.menuId == entry.value);
          if (orderedOpt != null && orderedOpt.menuId != opt.menuId) {
            await _client!.cancelMeal(
              date: entry.key,
              menuId: orderedOpt.menuId,
              locationId: orderedOpt.locationId,
              mealType: orderedOpt.mealType,
            );
          }
          await _client!.selectMeal(
            date: entry.key,
            menuId: opt.menuId,
            locationId: opt.locationId,
            mealType: opt.mealType,
          );
          successCount++;
          successfulDays.add(entry.key);
          await SubmissionLog.add({
            'date': entry.key,
            'menuName': opt.menuName,
            'menuId': opt.menuId,
            'description': opt.description,
            'submittedAt': DateTime.now().toIso8601String(),
            'aiPickMenuName': _aiPicks.containsKey(entry.key)
                ? options
                    .where((o) => o.menuId == _aiPicks[entry.key])
                    .firstOrNull
                    ?.menuName
                : null,
          });
        }
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
      }
    }

    if (successfulDays.isNotEmpty) {
      final trainingData = await TrainingStore.load();
      for (final date in successfulDays) {
        final options = _menu[date]!;
        final chosenId = _selections[date];
        final entry = <String, dynamic>{
          'date': date,
          'options': [
            for (final o in options)
              {
                'menu_name': o.menuName,
                'menu_id': o.menuId,
                'description': o.description,
                'chosen': o.menuId == chosenId,
              },
          ],
        };
        for (var w = 0; w < 3; w++) {
          trainingData.add(entry);
        }
      }
      await TrainingStore.save(trainingData);

      var prefs = await PreferencesStore.load();
      prefs = deriveAutoPreferences(
        trainingData: trainingData,
        currentPrefs: prefs,
      );
      await PreferencesStore.save(prefs);
      await _loadPredictor();
    }

    setState(() => _isSubmitting = false);

    if (!mounted) return;

    if (lastError != null) {
      showCenteredToast(context,
          '$successCount oddano, napaka: $lastError',
          color: kAccentRed);
    } else {
      showCenteredToast(context,
          'Uspesno oddano: $successCount izbir',
          color: kAccentGreen);
    }

    await _fetchMenu(week: _currentWeek);
  }

  // ── Helpers ──

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final dayName = _dayNames[date.weekday] ?? '';
    return '$dayName, ${date.day}. ${date.month}.';
  }

  String _formatDateShort(String dateStr) {
    final date = DateTime.parse(dateStr);
    return '${_dayNames[date.weekday]?.substring(0, 3) ?? ''} ${date.day}.${date.month}.';
  }

  // ── Absence ──

  Future<void> _showAbsenceDialog() async {
    if (_client == null) return;

    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: kAccentAmber,
                onPrimary: kBgTop,
                surface: kBgBottom,
                onSurface: kTextPrimary,
                onSurfaceVariant: kTextSecondary,
              ),
          dialogTheme: DialogThemeData(
            backgroundColor: kBgBottom,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    final fromStr = _fmtDateYmd(picked.start);
    final toStr = _fmtDateYmd(picked.end);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0x30FFFFFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kGlassBorder, width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_busy,
                          size: 20, color: kAccentRed),
                      const SizedBox(width: 8),
                      const Text('Odsotnost',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: kTextPrimary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          kAccentRed.withAlpha(0),
                          kAccentRed.withAlpha(80),
                          kAccentRed.withAlpha(0),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                      'Odjavi malico za vse dni od $fromStr do $toStr?\n\n'
                      'Vse narocene malice bodo odpovedane.',
                      style: const TextStyle(
                          fontSize: 14, color: kTextSecondary)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Prekliči'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                            backgroundColor: kAccentRed),
                        child: const Text('Odjavi'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    await _submitAbsence(picked.start, picked.end);
  }

  Future<void> _submitAbsence(DateTime from, DateTime to) async {
    setState(() => _isSubmitting = true);

    var cancelled = 0;
    var errors = 0;

    final dates = <String>[];
    var day = from;
    while (!day.isAfter(to)) {
      if (day.weekday <= DateTime.friday) {
        dates.add(_fmtDateYmd(day));
      }
      day = day.add(const Duration(days: 1));
    }

    final allOptions = <String, List<MealOption>>{..._menu};
    final missingDates =
        dates.where((d) => !allOptions.containsKey(d)).toSet();

    if (missingDates.isNotEmpty && _currentWeek != null) {
      for (var w = _currentWeek!; w <= _currentWeek! + 4; w++) {
        if (missingDates.isEmpty) break;
        try {
          final weekMenu = await _client!.getWeeklyMenu(week: w);
          for (final entry in weekMenu.entries) {
            if (missingDates.remove(entry.key)) {
              allOptions[entry.key] = entry.value;
            }
          }
        } catch (_) {
          break;
        }
      }
    }

    for (final dateStr in dates) {
      final options = allOptions[dateStr];
      if (options != null) {
        final orderedOpt =
            options.where((o) => o.status == 'ordered').firstOrNull;
        if (orderedOpt != null) {
          try {
            await _client!.cancelMeal(
              date: dateStr,
              menuId: orderedOpt.menuId,
              locationId: orderedOpt.locationId,
              mealType: orderedOpt.mealType,
            );
            cancelled++;
          } catch (_) {
            errors++;
          }
        }
      }

      await SubmissionLog.add({
        'date': dateStr,
        'menuName': 'Odsoten',
        'menuId': '__odsoten__',
        'description': 'Odsotnost',
        'submittedAt': DateTime.now().toIso8601String(),
      });
    }

    await AbsenceStore.add(_fmtDateYmd(from), _fmtDateYmd(to));

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    final msg = errors > 0
        ? 'Odjavljeno: $cancelled, napake: $errors'
        : cancelled > 0
            ? 'Odjavljeno: $cancelled dni'
            : 'Odsotnost zabelezena za ${dates.length} dni';
    showCenteredToast(context, msg);

    await _fetchMenu(week: _currentWeek);
  }

  String _fmtDateYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_autoLoginAttempted || (_isLoading && !_isLoggedIn)) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Meni')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isLoggedIn) return _buildLoginScreen();
    return _buildMenuScreen();
  }

  // ── Login screen ──

  Widget _buildLoginScreen() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Meni')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: GlassCard(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.restaurant_menu,
                      size: 56, color: kAccentAmber),
                  const SizedBox(height: 8),
                  const Text('eAsistent',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Uporabniško ime',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Geslo',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        style: const TextStyle(color: kAccentRed),
                        textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
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
      ),
    );
  }

  // ── Menu screen ──

  Widget _buildMenuScreen() {
    final submittable = _submittableSelections;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Tedenski meni'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Prejšnji teden',
            onPressed: _currentWeek != null && !_isLoading
                ? () => _fetchMenu(week: _currentWeek! - 1)
                : null,
          ),
          Center(
            child: GlassCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              radius: 10,
              child: Text('T${_currentWeek ?? '?'}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: kTextPrimary)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Naslednji teden',
            onPressed: _currentWeek != null && !_isLoading
                ? () => _fetchMenu(week: _currentWeek! + 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Osveži',
            onPressed:
                _isLoading ? null : () => _fetchMenu(week: _currentWeek),
          ),
          IconButton(
            icon: const Icon(Icons.event_busy),
            tooltip: 'Odsotnost',
            onPressed:
                _isLoading || _isSubmitting ? null : _showAbsenceDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isProbing)
            GlassBar(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kTextMuted),
                  ),
                  SizedBox(width: 8),
                  Text('Preverjam zaklenjenost...',
                      style: TextStyle(fontSize: 12, color: kTextMuted)),
                ],
              ),
            ),
          Expanded(child: _buildMenuBody()),
          if (submittable.isNotEmpty && !_isLoading)
            _buildSubmitBar(submittable),
        ],
      ),
    );
  }

  Widget _buildMenuBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
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
                onPressed: () => _fetchMenu(week: _currentWeek),
                child: const Text('Poskusi znova'),
              ),
            ],
          ),
        ),
      );
    }
    if (_menu.isEmpty) {
      return const Center(
        child: Text('Ni podatkov za ta teden',
            style: TextStyle(color: kTextMuted, fontSize: 16)),
      );
    }

    final sortedDates = _menu.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, _navBarPad),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final options = _menu[date]!;
        final selectable = _isDaySelectable(date);
        final selectedId = _selections[date];
        final aiPickId = _aiPicks[date];

        final orderedOpt =
            options.where((o) => o.status == 'ordered').firstOrNull;
        final isPartiallyLocked = _partiallyLockedDates.contains(date);

        return _DaySection(
          dateLabel: _formatDate(date),
          options: options,
          selectable: selectable,
          selectedId: selectedId,
          aiPickId: aiPickId,
          orderedId: orderedOpt?.menuId,
          isPartiallyLocked: isPartiallyLocked,
          getScore: (menuId) => _getScore(date, menuId),
          onTap: (opt) => _onOptionTap(date, opt),
          onCancelTap: () => _onCancelTap(date),
        );
      },
    );
  }

  Widget _buildSubmitBar(List<MapEntry<String, String>> submittable) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _navBarPad),
      child: GlassBar(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _confirmAndSubmit,
              icon: _isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(
                _isSubmitting
                    ? 'Oddajam...'
                    : 'Oddaj izbire (${submittable.length})',
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Day section
// ══════════════════════════════════════════════════════════════

class _DaySection extends StatelessWidget {
  final String dateLabel;
  final List<MealOption> options;
  final bool selectable;
  final String? selectedId;
  final String? aiPickId;
  final String? orderedId;
  final bool isPartiallyLocked;
  final double Function(String menuId) getScore;
  final void Function(MealOption) onTap;
  final VoidCallback onCancelTap;

  const _DaySection({
    required this.dateLabel,
    required this.options,
    required this.selectable,
    required this.selectedId,
    required this.aiPickId,
    required this.orderedId,
    required this.isPartiallyLocked,
    required this.getScore,
    required this.onTap,
    required this.onCancelTap,
  });

  /// Build a compact lock badge label from the locked options (index > 0).
  String _lockBadgeLabel() {
    if (options.length <= 1) return '';
    final locked = options.sublist(1);
    // Try to extract menu numbers for a compact range display
    final numbers = <int>[];
    final numRe = RegExp(r'(\d+)');
    for (final opt in locked) {
      final m = numRe.firstMatch(opt.menuName);
      if (m != null) numbers.add(int.parse(m.group(1)!));
    }
    if (numbers.length == locked.length && numbers.isNotEmpty) {
      numbers.sort();
      final prefix = locked.first.menuName.contains(RegExp(r'[Mm]eni'))
          ? 'Meni '
          : '#';
      if (numbers.length == 1) return '$prefix${numbers.first}';
      return '$prefix${numbers.first}-${numbers.last}';
    }
    return '${locked.length} zakl.';
  }

  @override
  Widget build(BuildContext context) {
    final hasOrder = orderedId != null;
    final isCancelSelected = selectedId == _cancelId;
    final isOverriding = hasOrder &&
        selectedId != null &&
        selectedId != orderedId &&
        !isCancelSelected;

    Color barColor;
    if (isCancelSelected) {
      barColor = kAccentRed;
    } else if (isOverriding) {
      barColor = kAccentYellow;
    } else if (hasOrder) {
      barColor = kAccentGreen;
    } else if (selectable) {
      barColor = kAccentAmber;
    } else {
      barColor = kTextMuted;
    }

    final showLockBadge = isPartiallyLocked && !isCancelSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day header
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 2),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(dateLabel,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary)),
              ),
              if (showLockBadge) ...[
                PillChip(
                    label: _lockBadgeLabel(),
                    color: kTextMuted,
                    icon: Icons.lock_outline),
                const SizedBox(width: 4),
              ],
              if (isCancelSelected && hasOrder)
                const PillChip(label: 'Odjavljen', color: kAccentRed)
              else if (hasOrder)
                PillChip(
                  label:
                      'eA: ${options.firstWhere((o) => o.menuId == orderedId).menuName}',
                  color: isOverriding ? kAccentYellow : kAccentGreen,
                ),
            ],
          ),
        ),
        // Gradient line separator
        Container(
          height: 1,
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                barColor.withAlpha(0),
                barColor.withAlpha(90),
                barColor.withAlpha(0),
              ],
            ),
          ),
        ),
        // Meal cards
        ...options.asMap().entries.map((e) {
          final idx = e.key;
          final opt = e.value;
          final lockedOut = isPartiallyLocked && idx > 0;
          final tappable = selectable &&
              !lockedOut &&
              (opt.status == 'available' || opt.status == 'ordered');
          final isSelected =
              tappable && !isCancelSelected && selectedId == opt.menuId;
          final isAiPick = tappable && aiPickId == opt.menuId;
          final isOrdered = opt.menuId == orderedId;
          final score = tappable ? getScore(opt.menuId) : null;

          return AnimatedOpacity(
            opacity: lockedOut ? 0.4 : 1.0,
            duration: const Duration(milliseconds: 250),
            child: _MealCard(
              option: opt,
              isSelected: isSelected,
              isAiPick: isAiPick,
              isOrdered: isOrdered,
              score: score,
              healthScore: opt.description.isNotEmpty
                  ? scoreMeal(opt.description).score
                  : null,
              tappable: tappable,
              onTap: () => onTap(opt),
            ),
          );
        }),
        if (selectable) _buildCancelPill(isCancelSelected),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildCancelPill(bool isSelected) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: GlassCard(
          selected: isSelected,
          borderColor: kAccentRed,
          radius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          onTap: onCancelTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.cancel_outlined,
                size: 15,
                color: isSelected ? kAccentRed : kTextMuted,
              ),
              const SizedBox(width: 6),
              Text(
                'Odjava',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: isSelected ? kAccentRed : kTextMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Meal card
// ══════════════════════════════════════════════════════════════

class _MealCard extends StatelessWidget {
  final MealOption option;
  final bool isSelected;
  final bool isAiPick;
  final bool isOrdered;
  final double? score;
  final int? healthScore;
  final bool tappable;
  final VoidCallback onTap;

  const _MealCard({
    required this.option,
    required this.isSelected,
    required this.isAiPick,
    required this.isOrdered,
    required this.score,
    this.healthScore,
    required this.tappable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = menuColor(option.menuName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GlassCard(
        selected: isSelected,
        borderColor: accent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: tappable ? onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: radio + name left, pills + score right
            Row(
              children: [
                if (tappable || isSelected) ...[
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      key: ValueKey(isSelected),
                      size: 18,
                      color: isSelected ? accent : kTextMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    option.menuName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isSelected
                          ? accent
                          : (tappable ? kTextPrimary : kTextMuted),
                    ),
                  ),
                ),
                if (isAiPick) ...[
                  PillChip(label: 'AI', color: kAccentMauve.withAlpha(200)),
                  const SizedBox(width: 6),
                ],
                if (isOrdered) ...[
                  const PillChip(label: 'eA', color: kAccentYellow),
                  const SizedBox(width: 6),
                ],
                if (option.status == 'cancelled') ...[
                  const PillChip(label: 'Odjavljen', color: kTextMuted),
                  const SizedBox(width: 6),
                ],
                if (healthScore != null) ...[
                  _buildHealthDot(),
                  const SizedBox(width: 6),
                ],
                if (score != null) _buildScoreGlow(),
              ],
            ),
            // Description
            if (option.description.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(option.description,
                  style: TextStyle(
                      fontSize: 12,
                      color: tappable ? kTextSecondary : kTextMuted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthDot() {
    final hs = healthScore!;
    final color = hs >= 7 ? kAccentGreen : (hs >= 4 ? kAccentYellow : kAccentRed);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withAlpha(120), blurRadius: 4, spreadRadius: 0),
        ],
      ),
    );
  }

  Widget _buildScoreGlow() {
    final isPositive = score! >= 0;
    final color = isPositive ? kAccentGreen : kAccentRed;
    final text = isPositive
        ? '+${score!.toStringAsFixed(2)}'
        : score!.toStringAsFixed(2);

    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
        shadows: [
          Shadow(color: color.withAlpha(120), blurRadius: 8),
        ],
      ),
    );
  }
}

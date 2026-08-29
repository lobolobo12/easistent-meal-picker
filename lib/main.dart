import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'screens/menu_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/training_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/log_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/health_screen.dart';
import 'services/onboarding_store.dart';
import 'services/scheduler_service.dart';
import 'services/rating_store.dart';
import 'services/submission_log.dart';
import 'theme.dart';

/// Global navigator key so we can show the rating dialog from notification tap.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initScheduler();

  // Home widget: set Android widget provider name for click-to-open.
  // Android-only — see updateHomeWidget in services/widget_service.dart.
  if (Platform.isAndroid) {
    HomeWidget.setAppGroupId('com.easistent.mealpicker');
  }

  // Wire up notification tap handler
  onNotificationTap = (payload) {
    if (payload == 'auto_submit') {
      // iOS Monday-18:00 prompt: the submit itself runs in the catch-up.
      runForegroundCatchUp();
      return;
    }
    if (payload == 'rate_meal') {
      // Small delay to ensure the app is fully rendered
      Future.delayed(const Duration(milliseconds: 500), () {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          showRatingDialog(ctx);
        }
      });
    }
  };

  runApp(const MealPickerApp());
}

class MealPickerApp extends StatefulWidget {
  const MealPickerApp({super.key});

  @override
  State<MealPickerApp> createState() => _MealPickerAppState();
}

class _MealPickerAppState extends State<MealPickerApp>
    with WidgetsBindingObserver {
  bool? _onboardingDone;
  bool _showTour = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OnboardingStore.isComplete().then((done) {
      if (mounted) setState(() => _onboardingDone = done);
      // On iOS the scheduled work can only run while the app is alive, so
      // catch up on anything its alarms would have done. No-op on Android
      // and when onboarding has not been completed (no credentials yet).
      if (done) runForegroundCatchUp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _onboardingDone == true) {
      runForegroundCatchUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'eAsistent Meal Picker',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _onboardingDone == null
          ? Container(
              decoration: const BoxDecoration(gradient: kBgGradient),
              child: const Center(child: CircularProgressIndicator()),
            )
          : _onboardingDone!
              ? MainShell(showTour: _showTour)
              : OnboardingScreen(
                  onComplete: () => setState(() {
                    _onboardingDone = true;
                    _showTour = true;
                  }),
                ),
    );
  }
}

// ── Main shell with gradient + floating nav ──

class MainShell extends StatefulWidget {
  final bool showTour;
  const MainShell({super.key, this.showTour = false});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int? _tourStep;

  final _menuKey = GlobalKey<MenuScreenState>();
  final _settingsKey = GlobalKey<SettingsScreenState>();
  final _navItemKeys = List.generate(6, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    if (widget.showTour) {
      // Wait for first frame + nav bar expand animation before showing overlay
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) setState(() => _tourStep = 0);
        });
      });
    }
  }

  /// Which tab each tour step should show (steps 0-5 = nav items, 6-12 = feature cards).
  static const _tourTabForStep = [0, 1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0];

  void _nextTourStep() {
    final next = (_tourStep ?? 0) + 1;
    if (next >= 13) {
      setState(() {
        _tourStep = null;
        _currentIndex = 0;
      });
      return;
    }
    final targetTab = _tourTabForStep[next];
    if (next < 6) {
      // Nav spotlight steps: hide overlay, switch tab, re-show after expand animation
      setState(() {
        _tourStep = null;
        _currentIndex = targetTab;
      });
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) setState(() => _tourStep = next);
      });
    } else {
      // Feature card steps: no spotlight, switch tab if needed, show immediately
      setState(() {
        _tourStep = next;
        _currentIndex = targetTab;
      });
    }
  }

  void _endTour() {
    setState(() {
      _tourStep = null;
      _currentIndex = 0;
    });
  }

  void _onLogout() {
    _menuKey.currentState?.logout();
    setState(() => _currentIndex = 0);
  }

  void _onTabChanged(int i) {
    setState(() => _currentIndex = i);
    if (i == 5) _settingsKey.currentState?.reloadPrefs();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: kBgBase,
          body: IndexedStack(
            index: _currentIndex,
            children: [
              MenuScreen(key: _menuKey),
              const TrainingScreen(),
              const StatsScreen(),
              const HealthScreen(),
              const LogScreen(),
              SettingsScreen(key: _settingsKey, onLogout: _onLogout),
            ],
          ),
          bottomNavigationBar: _TabBar(
            selectedIndex: _currentIndex,
            onTap: _onTabChanged,
            itemKeys: _navItemKeys,
          ),
        ),
        // Feature tour overlay
        if (_tourStep != null)
          _TourOverlay(
            step: _tourStep!,
            targetKey: _tourStep! < 6 ? _navItemKeys[_tourStep!] : null,
            onNext: _nextTourStep,
            onSkip: _endTour,
          ),
      ],
    );
  }
}

// ── iOS tab bar ──

/// Standard iOS bottom tab bar: full-bleed, anchored above the home
/// indicator, hairline rule on top, icon over a small always-visible label.
/// Replaces the floating glass pill, which overlapped screen content and read
/// as distinctly non-native.
class _TabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<GlobalKey>? itemKeys;

  const _TabBar({
    required this.selectedIndex,
    required this.onTap,
    this.itemKeys,
  });

  static const _items = [
    (CupertinoIcons.list_bullet, 'Meni'),
    (CupertinoIcons.wand_stars, 'Trening'),
    (CupertinoIcons.chart_bar_alt_fill, 'Statistika'),
    (CupertinoIcons.heart_fill, 'Zdravje'),
    (CupertinoIcons.clock_fill, 'Dnevnik'),
    (CupertinoIcons.gear_alt_fill, 'Nastavitve'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBgBase,
        border: Border(top: BorderSide(color: kSeparator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 49,
          child: Row(
            children: List.generate(_items.length, (i) {
              final sel = i == selectedIndex;
              final color = sel ? kAccent : kLabelTertiary;
              return Expanded(
                child: GestureDetector(
                  key: itemKeys?[i],
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_items[i].$1, size: 22, color: color),
                      const SizedBox(height: 2),
                      Text(
                        _items[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}


// ── Rating dialog ──

/// Show a 1-5 star rating dialog for today's meal.
///
/// Looks up today's submission in the log to show what was eaten.
/// Can also be called manually from the UI.
Future<void> showRatingDialog(BuildContext context) async {
  final now = DateTime.now();
  final todayStr =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  // Check if already rated
  final alreadyRated = await RatingStore.hasRatingForDate(todayStr);
  if (alreadyRated) {
    if (context.mounted) {
      showCenteredToast(context, 'Danes že ocenjeno!');
    }
    return;
  }

  // Find today's submission
  final log = await SubmissionLog.load();
  final todayEntry = log.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e!['date'] == todayStr && e['menuName'] != 'Odjava',
        orElse: () => null,
      );

  if (todayEntry == null) {
    if (context.mounted) {
      showCenteredToast(context, 'Ni oddaje za danes.');
    }
    return;
  }

  final menuName = todayEntry['menuName'] as String? ?? '';
  final description = todayEntry['description'] as String? ?? '';

  if (!context.mounted) return;

  final rating = await showDialog<int>(
    context: context,
    builder: (ctx) => _RatingDialog(
      menuName: menuName,
      description: description,
    ),
  );

  if (rating != null && context.mounted) {
    await RatingStore.add({
      'date': todayStr,
      'menuName': menuName,
      'description': description,
      'rating': rating,
      'ratedAt': DateTime.now().toIso8601String(),
    });
    if (context.mounted) {
      showCenteredToast(context, 'Ocena $rating/5 shranjena!');
    }
  }
}

class _RatingDialog extends StatefulWidget {
  final String menuName;
  final String description;

  const _RatingDialog({
    required this.menuName,
    required this.description,
  });

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _selected = 0;

  String _cleanDesc(String desc) {
    return desc
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .trim()
        .replaceAll(RegExp(r',\s*$'), '');
  }

  Color get _starColor {
    if (_selected <= 1) return kAccentRed;
    if (_selected == 2) return kAccentAmber;
    if (_selected == 3) return kAccentYellow;
    if (_selected == 4) return kAccentGreen;
    return kAccentTeal;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
              boxShadow: _selected > 0
                  ? [
                      BoxShadow(
                        color: _starColor.withAlpha(30),
                        blurRadius: 24,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Oceni malico',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary)),
                const SizedBox(height: 12),
                Text(widget.menuName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kAccentAmber,
                      shadows: [
                        Shadow(
                            color: kAccentAmber.withAlpha(80), blurRadius: 6),
                      ],
                    )),
                if (widget.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_cleanDesc(widget.description),
                      style:
                          const TextStyle(fontSize: 13, color: kTextSecondary),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                // Stars with glow
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    final active = star <= _selected;
                    return GestureDetector(
                      onTap: () => setState(() => _selected = star),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: AnimatedScale(
                          scale: active ? 1.15 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            active
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 40,
                            color: active ? _starColor : kTextMuted,
                            shadows: active
                                ? [
                                    Shadow(
                                      color: _starColor.withAlpha(150),
                                      blurRadius: 12,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                if (_selected > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    _ratingLabel(_selected),
                    style: TextStyle(
                      fontSize: 13,
                      color: _starColor,
                      shadows: [
                        Shadow(
                            color: _starColor.withAlpha(100), blurRadius: 6),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Prekliči'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _selected > 0
                          ? () => Navigator.pop(context, _selected)
                          : null,
                      child: const Text('Shrani'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Grozno';
      case 2:
        return 'Slabo';
      case 3:
        return 'OK';
      case 4:
        return 'Dobro';
      case 5:
        return 'Odlično';
      default:
        return '';
    }
  }
}

// ── Feature tour overlay ──

class _TourOverlay extends StatelessWidget {
  final int step;
  final GlobalKey? targetKey;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TourOverlay({
    required this.step,
    this.targetKey,
    required this.onNext,
    required this.onSkip,
  });

  static const _totalSteps = 13;

  // Steps 0-5: nav bar spotlight steps
  static const _navSteps = [
    (Icons.restaurant_menu, 'Meni',
        'Tedenski meni z AI priporočili. Izberi obrok za vsak dan in oddaj.'),
    (Icons.fitness_center, 'Trening',
        'Treniraj AI z izbiranjem med jedmi. Več kot treniraš, boljše napovedi.'),
    (Icons.bar_chart, 'Statistika',
        'Pregled statistike tvojih izbir in točnosti AI napovedi.'),
    (Icons.favorite, 'Zdravje',
        'Zdravstvena ocena jedilnika na podlagi sestavin.'),
    (Icons.history, 'Dnevnik',
        'Zgodovina vseh oddanih izbir in ocen obrokov.'),
    (Icons.settings, 'Nastavitve',
        'Nastavi všečne/nevšečne besede in vrstni red menijev.'),
  ];

  // Steps 6-12: centered feature explanation cards
  static const _featureSteps = [
    (Icons.auto_awesome, kAccentMauve, 'AI priporočilo',
        'Vijolična zvezdica označuje jed, ki jo AI priporoča na podlagi tvojega treninga in nastavitev.'),
    (Icons.favorite, kAccentGreen, 'Zdravstvena ocena',
        'Zelena = zdravo (7–10), rumena = srednje (4–6), rdeča = manj zdravo (1–3). Zlata/srebrna/bronasta značka označuje najboljšo jed dneva.'),
    (Icons.check_circle, kAccentYellow, 'eA značka',
        'Rumena \'eA\' značka pomeni, da je ta jed že naročena na eAsistent.'),
    (Icons.lock, kAccentRed, 'Zaklenjen dan',
        'Ključavnica pomeni, da je eAsistent zaklenil izbiro za ta dan. Meni 2–8 so zamrznjeni, Meni 1 in Odjava sta še na voljo.'),
    (Icons.event_busy, kAccentAmber, 'Odsotnost',
        'Če te ne bo v šoli, tapni gumb za odsotnost. Odjava se pošlje za izbrane dni, tako da ne zapravljaš obrokov.'),
    (Icons.star_rounded, kAccentYellow, 'Ocena obroka',
        'Vsak dan ob 13:00 dobiš obvestilo za oceno malice. Tvoje ocene pomagajo AI-ju izboljšati prihodnje napovedi.'),
    (Icons.schedule, kAccentTeal, 'Samodejna oddaja',
        'Ob ponedeljkih ob 18:00 AI samodejno odda najboljše izbire za naslednji teden. Ob 16:00 dobiš opomnik, da lahko še preveriš.'),
  ];

  @override
  Widget build(BuildContext context) {
    if (step < 6) {
      return _buildSpotlightStep(context);
    } else {
      return _buildFeatureCard(context);
    }
  }

  Widget _buildSpotlightStep(BuildContext context) {
    final renderBox =
        targetKey?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return const SizedBox.shrink();

    final pos = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final center = pos + Offset(size.width / 2, size.height / 2);
    final radius =
        (size.width > size.height ? size.width : size.height) / 2 + 14;

    final (icon, title, desc) = _navSteps[step];

    return GestureDetector(
      onTap: onNext,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SpotlightPainter(center: center, radius: radius),
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).size.height - pos.dy + 16,
              left: 24,
              right: 24,
              child: _buildTooltipCard(icon, title, desc, kAccentAmber),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(BuildContext context) {
    final featureIdx = step - 6;
    final (icon, color, title, desc) = _featureSteps[featureIdx];

    return GestureDetector(
      onTap: onNext,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: Stack(
          children: [
            // Full dark overlay (no cutout)
            Positioned.fill(
              child: Container(color: const Color(0xCC000000)),
            ),
            // Centered card
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _buildTooltipCard(icon, title, desc, color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTooltipCard(IconData icon, String title, String desc, Color accent) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0x30FFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kGlassBorder, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: accent.withAlpha(30),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: accent),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                    decoration: TextDecoration.none,
                  )),
              const SizedBox(height: 6),
              Text(desc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: kTextSecondary,
                    decoration: TextDecoration.none,
                  )),
              const SizedBox(height: 16),
              // Step progress
              _buildStepIndicator(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: onSkip,
                    child: const Text('Preskoči',
                        style: TextStyle(
                          fontSize: 13,
                          color: kTextMuted,
                          decoration: TextDecoration.none,
                        )),
                  ),
                  Text(
                    step < _totalSteps - 1 ? 'Tapni za naprej' : 'Tapni za konec',
                    style: const TextStyle(
                      fontSize: 13,
                      color: kAccentAmber,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    // Two-phase indicator: nav dots (0-5) and feature dots (6-12)
    final inNav = step < 6;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Nav phase dots
        for (var i = 0; i < 6; i++)
          Container(
            width: i == step ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: i == step
                  ? kAccentAmber
                  : i < step
                      ? kAccentAmber.withAlpha(100)
                      : kTextMuted.withAlpha(60),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        // Divider
        Container(
          width: 1,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: inNav ? kTextMuted.withAlpha(40) : kAccentAmber.withAlpha(60),
        ),
        // Feature phase dots
        for (var i = 6; i < _totalSteps; i++)
          Container(
            width: i == step ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: i == step
                  ? kAccentAmber
                  : i < step
                      ? kAccentAmber.withAlpha(100)
                      : kTextMuted.withAlpha(60),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Offset center;
  final double radius;

  _SpotlightPainter({required this.center, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xCC000000);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.center != center || old.radius != radius;
}

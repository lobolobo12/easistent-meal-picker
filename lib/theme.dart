import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// iOS-native design system.
///
/// Colours, type and spacing follow Apple's Human Interface Guidelines dark
/// mode rather than inventing values per widget. Everything here is a token —
/// screens should reference these, never raw numbers.
///
/// Legacy `kGlass*` / `GlassCard` names are kept as aliases so the screens
/// written against the old glassmorphism theme keep compiling; they now render
/// as iOS grouped surfaces.

// ── System backgrounds (HIG dark, grouped hierarchy) ──
//
// iOS layers grouped content: a near-black ground, rows one step lighter,
// and selected/nested content one step lighter again. Depth comes from these
// steps, not from blur or glow.

const kBgBase = Color(0xFF000000); // systemGroupedBackground
const kBgElevated = Color(0xFF1C1C1E); // secondarySystemGroupedBackground
const kBgElevated2 = Color(0xFF2C2C2E); // tertiarySystemGroupedBackground
const kBgElevated3 = Color(0xFF3A3A3C);

const kSeparator = Color(0xFF38383A); // opaque separator
const kSeparatorThin = Color(0x5C545458); // non-opaque separator

// ── Labels ──

const kLabel = Color(0xFFFFFFFF);
const kLabelSecondary = Color(0x99EBEBF5); // 60%
const kLabelTertiary = Color(0x4DEBEBF5); // 30%
const kLabelQuaternary = Color(0x2DEBEBF5); // 18%

// ── System accents (HIG dark variants) ──

const kBlue = Color(0xFF0A84FF);
const kGreen = Color(0xFF30D158);
const kIndigo = Color(0xFF5E5CE6);
const kOrange = Color(0xFFFF9F0A);
const kPink = Color(0xFFFF375F);
const kPurple = Color(0xFFBF5AF2);
const kRed = Color(0xFFFF453A);
const kTeal = Color(0xFF64D2FF);
const kYellow = Color(0xFFFFD60A);

/// The single app accent. One tint, used for interaction — not decoration.
const kAccent = kOrange;

// ── Spacing: 4pt grid ──

const double kSp2 = 2;
const double kSp4 = 4;
const double kSp8 = 8;
const double kSp12 = 12;
const double kSp16 = 16; // standard iOS screen margin
const double kSp20 = 20;
const double kSp24 = 24;
const double kSp32 = 32;

// ── Radii ──

const double kRadiusRow = 10; // inset grouped list
const double kRadiusCard = 12;
const double kRadiusSheet = 20;

// ── Type scale (iOS text styles) ──
//
// No fontFamily is set anywhere: on iOS that resolves to San Francisco, which
// is what makes the app read as native.

const kLargeTitle = TextStyle(
    fontSize: 34, fontWeight: FontWeight.w700, color: kLabel, height: 1.2);
const kTitle1 = TextStyle(
    fontSize: 28, fontWeight: FontWeight.w700, color: kLabel, height: 1.2);
const kTitle2 = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w700, color: kLabel, height: 1.25);
const kTitle3 = TextStyle(
    fontSize: 20, fontWeight: FontWeight.w600, color: kLabel, height: 1.25);
const kHeadline = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w600, color: kLabel, height: 1.3);
const kBody = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w400, color: kLabel, height: 1.35);
const kCallout = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w400, color: kLabel, height: 1.35);
const kSubhead = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w400, color: kLabelSecondary,
    height: 1.35);
const kFootnote = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w400, color: kLabelSecondary,
    height: 1.35);
const kCaption = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w400, color: kLabelSecondary,
    height: 1.3);
const kCaption2 = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w400, color: kLabelTertiary,
    height: 1.3);

// ── Legacy aliases ──
//
// The screens were written against the old glass theme. Rather than touch
// 6,000 lines at once, the old names now point at HIG tokens.

const kBgTop = kBgBase;
const kBgBottom = kBgBase;
const kGlassFill = kBgElevated;
const kGlassBorder = kSeparatorThin;
const kGlassSelected = kBgElevated2;

const kTextPrimary = kLabel;
const kTextSecondary = kLabelSecondary;
const kTextMuted = kLabelTertiary;

const kAccentAmber = kOrange;
const kAccentGreen = kGreen;
const kAccentPurple = kPurple;
const kAccentBlue = kBlue;
const kAccentTeal = kTeal;
const kAccentRed = kRed;
const kAccentMauve = kIndigo;
const kAccentYellow = kYellow;

/// Flat ground. Kept as a gradient so existing `BoxDecoration(gradient:)`
/// call sites still work, but iOS uses a solid grouped background.
const kBgGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kBgBase, kBgBase],
);

// ── Menu-type → accent ──

const _menuPalette = [kBlue, kGreen, kIndigo, kTeal, kPurple];

/// Colour for a menu name. Used sparingly — as a small leading dot or a
/// selected-row tint, never as a full-card wash.
Color menuColor(String menuName) {
  final l = menuName.toLowerCase().trim();
  if (l.contains('fit')) return kPurple;
  if (l.contains('xxl')) return kBlue;
  if (l.contains('vegan')) return kTeal;
  if (l.contains('vegetarijan') || l.contains('veg')) return kGreen;
  final m = RegExp(r'(\d+)').firstMatch(l);
  if (m != null) {
    final num = int.tryParse(m.group(1)!) ?? 1;
    return _menuPalette[(num - 1) % _menuPalette.length];
  }
  return kAccent;
}

// ── Inset grouped list ──

/// iOS grouped-list section: an optional upper-case header, then rows in a
/// single rounded container with hairline separators between them.
class InsetGroup extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;
  final EdgeInsets margin;

  const InsetGroup({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: kSp24),
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Padding(
          padding: EdgeInsets.only(left: kSp16),
          child: Divider(
              height: 0.5, thickness: 0.5, color: kSeparator),
        ));
      }
    }

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(kSp16, 0, kSp16, kSp8),
              child: Text(header!.toUpperCase(),
                  style: kFootnote.copyWith(
                      color: kLabelSecondary, letterSpacing: 0.5)),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(kRadiusRow),
            child: ColoredBox(
              color: kBgElevated,
              child: Column(children: rows),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(kSp16, kSp8, kSp16, 0),
              child: Text(footer!, style: kFootnote),
            ),
        ],
      ),
    );
  }
}

/// A single row inside an [InsetGroup]: leading icon, title, optional
/// subtitle, trailing value and chevron. 44pt minimum height per HIG.
class InsetRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? value;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  const InsetRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: kSp16, vertical: kSp8),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: iconColor ?? kAccent),
                  const SizedBox(width: kSp12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: kBody),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: kSp2),
                          child: Text(subtitle!, style: kFootnote),
                        ),
                    ],
                  ),
                ),
                if (value != null)
                  Padding(
                    padding: const EdgeInsets.only(left: kSp8),
                    child: Text(value!,
                        style: kBody.copyWith(color: kLabelSecondary)),
                  ),
                if (trailing != null) ...[
                  const SizedBox(width: kSp8),
                  trailing!,
                ],
                if (showChevron)
                  const Padding(
                    padding: EdgeInsets.only(left: kSp4),
                    child: Icon(CupertinoIcons.chevron_right,
                        size: 14, color: kLabelTertiary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Free-standing section header for screens that aren't grouped lists.
class SectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const SectionHeader(this.label, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSp16, kSp8, kSp16, kSp8),
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(),
                style: kFootnote.copyWith(
                    color: kLabelSecondary, letterSpacing: 0.5)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ── Card surface (legacy name, iOS styling) ──

/// An elevated iOS surface. Formerly a blurred glass panel; now a flat
/// grouped-background card. Selection is shown with a tinted fill and a
/// 1pt accent border, not a coloured glow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final bool selected;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(kSp16),
    this.margin = EdgeInsets.zero,
    this.radius = kRadiusCard,
    this.selected = false,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final accent = borderColor ?? kAccent;

    return Padding(
      padding: margin,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.16) : kBgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: br,
          side: selected
              ? BorderSide(color: accent, width: 1)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Top bar strip. Solid iOS navigation-bar fill with a hairline bottom rule.
class GlassBar extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const GlassBar({
    super.key,
    required this.child,
    this.padding =
        const EdgeInsets.symmetric(horizontal: kSp16, vertical: kSp12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: const BoxDecoration(
        color: kBgBase,
        border: Border(bottom: BorderSide(color: kSeparator, width: 0.5)),
      ),
      child: child,
    );
  }
}

/// Small status badge. iOS uses these sparingly, so keep them quiet.
class PillChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const PillChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kSp8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: kSp4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── App-wide ThemeData ──

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    // Resolves to San Francisco on iOS — the single biggest cue that an app
    // belongs on the platform.
    typography: Typography.material2021(platform: TargetPlatform.iOS),
    scaffoldBackgroundColor: kBgBase,
    canvasColor: kBgBase,
    splashFactory: NoSplash.splashFactory,
    highlightColor: kLabelQuaternary,
    colorScheme: const ColorScheme.dark(
      primary: kAccent,
      onPrimary: Colors.black,
      secondary: kBlue,
      surface: kBgElevated,
      onSurface: kLabel,
      error: kRed,
    ),
    // iOS large navigation title: left-aligned, 34pt, sitting on the screen
    // margin. Setting it here gives every screen the platform title without
    // converting each one to a sliver app bar.
    appBarTheme: const AppBarTheme(
      backgroundColor: kBgBase,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: kSp16,
      toolbarHeight: 88,
      foregroundColor: kLabel,
      titleTextStyle: kLargeTitle,
      actionsIconTheme: IconThemeData(color: kAccent, size: 22),
      iconTheme: IconThemeData(color: kAccent, size: 22),
    ),
    cardColor: kBgElevated,
    dividerColor: kSeparator,
    dividerTheme: const DividerThemeData(
        color: kSeparator, thickness: 0.5, space: 0.5),
    listTileTheme: const ListTileThemeData(
      titleTextStyle: kBody,
      subtitleTextStyle: kFootnote,
      iconColor: kAccent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kBgElevated2,
      contentTextStyle: kSubhead.copyWith(color: kLabel),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kBgElevated2,
      surfaceTintColor: Colors.transparent,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSheet)),
      titleTextStyle: kHeadline,
      contentTextStyle: kSubhead,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(50),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
        textStyle: kHeadline.copyWith(color: Colors.black),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kAccent,
        textStyle: kBody,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kAccent,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: kSeparator),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
        textStyle: kBody,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kBgElevated2,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: kSp12, vertical: kSp12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusRow),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusRow),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusRow),
        borderSide: const BorderSide(color: kAccent, width: 1.5),
      ),
      labelStyle: kSubhead,
      hintStyle: kSubhead.copyWith(color: kLabelTertiary),
      prefixIconColor: kLabelSecondary,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kBgElevated2,
      side: BorderSide.none,
      labelStyle: kFootnote.copyWith(color: kLabel),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? kGreen : kBgElevated3),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kAccent,
      linearTrackColor: kBgElevated2,
      circularTrackColor: kBgElevated2,
    ),
  );
}

// ── Centered toast overlay ──

/// Auto-dismissing centred toast. iOS-flavoured: solid material, no glow.
void showCenteredToast(BuildContext context, String message, {Color? color}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => _CenteredToast(
      message: message,
      color: color,
      onDismiss: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _CenteredToast extends StatefulWidget {
  final String message;
  final Color? color;
  final VoidCallback onDismiss;

  const _CenteredToast({
    required this.message,
    this.color,
    required this.onDismiss,
  });

  @override
  State<_CenteredToast> createState() => _CenteredToastState();
}

class _CenteredToastState extends State<_CenteredToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_ctrl);
    _ctrl.forward().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: _opacity,
            builder: (ctx, child) =>
                Opacity(opacity: _opacity.value, child: child),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: kSp32),
              padding: const EdgeInsets.symmetric(
                  horizontal: kSp20, vertical: kSp16),
              decoration: BoxDecoration(
                color: kBgElevated2,
                borderRadius: BorderRadius.circular(kRadiusSheet),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (accent != null) ...[
                    Container(
                      width: 3,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: kSp12),
                  ],
                  Flexible(
                    child: Text(
                      widget.message,
                      textAlign:
                          accent != null ? TextAlign.left : TextAlign.center,
                      style: const TextStyle(
                        color: kLabel,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
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
}

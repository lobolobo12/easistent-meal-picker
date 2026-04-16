import 'dart:ui';

import 'package:flutter/material.dart';

// ── Background gradient ──

const kBgTop = Color(0xFF0b0f1a);
const kBgBottom = Color(0xFF1a1d2e);

const kBgGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kBgTop, kBgBottom],
);

// ── Glass colors ──

const kGlassFill = Color(0x14FFFFFF); // ~8% white
const kGlassBorder = Color(0x28FFFFFF); // ~16% white
const kGlassSelected = Color(0x20FFFFFF); // ~12% white

// ── Text colors ──

const kTextPrimary = Color(0xFFe2e8f0);
const kTextSecondary = Color(0xFFa0aec0);
const kTextMuted = Color(0xFF64748b);

// ── Accent colors ──

const kAccentAmber = Color(0xFFf6ad55); // warm orange — meat / default
const kAccentGreen = Color(0xFF68d391); // green — veg
const kAccentPurple = Color(0xFFb794f6); // purple — fit
const kAccentBlue = Color(0xFF63b3ed); // blue — XXL
const kAccentTeal = Color(0xFF4fd1c5); // teal — vegan
const kAccentRed = Color(0xFFfc8181); // red — errors / cancel
const kAccentMauve = Color(0xFFd6bcfa); // mauve — AI indicator
const kAccentYellow = Color(0xFFfbd38d); // yellow — warnings / eA ordered

// ── Menu‑type → accent color ──

const _menuPalette = [
  kAccentAmber, kAccentGreen, kAccentPurple, kAccentBlue, kAccentTeal,
];

Color menuColor(String menuName) {
  final l = menuName.toLowerCase().trim();
  // Keyword hints — work for any school's naming convention
  if (l.contains('fit')) return kAccentPurple;
  if (l.contains('xxl')) return kAccentBlue;
  if (l.contains('vegan')) return kAccentTeal;
  if (l.contains('vegetarijan') || l.contains('veg')) return kAccentGreen;
  // Number-based: extract first digit and cycle through palette
  final m = RegExp(r'(\d+)').firstMatch(l);
  if (m != null) {
    final num = int.tryParse(m.group(1)!) ?? 1;
    return _menuPalette[(num - 1) % _menuPalette.length];
  }
  return kAccentAmber;
}

// ── GlassCard — reusable glassmorphism container ──

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
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.radius = 16,
    this.selected = false,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final effectiveBorder = selected && borderColor != null
        ? borderColor!
        : kGlassBorder;
    final effectiveWidth = selected ? 1.5 : 0.5;
    final fill = selected
        ? (borderColor ?? kGlassFill).withAlpha(30)
        : kGlassFill;

    Widget card = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: br,
            side: BorderSide(color: effectiveBorder, width: effectiveWidth),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: br,
            splashColor: Colors.white.withAlpha(12),
            highlightColor: Colors.white.withAlpha(8),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );

    if (selected && borderColor != null) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          boxShadow: [
            BoxShadow(
              color: borderColor!.withAlpha(50),
              blurRadius: 14,
              spreadRadius: 0,
            ),
          ],
        ),
        child: card,
      );
    }

    return Padding(padding: margin, child: card);
  }
}

// ── GlassBar — thin glass strip (app bars, stat bars) ──

class GlassBar extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const GlassBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: const BoxDecoration(
            color: kGlassFill,
            border: Border(bottom: BorderSide(color: kGlassBorder, width: 0.5)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── Pill chip — small tag ──

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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── App‑wide ThemeData ──

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kAccentAmber,
      brightness: Brightness.dark,
      surface: Colors.transparent,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: kTextPrimary,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: kTextPrimary,
      ),
    ),
    cardColor: kGlassFill,
    dividerColor: kGlassBorder,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xE6181c2a),
      contentTextStyle: const TextStyle(color: kTextPrimary, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF1a1d2e),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: kTextPrimary),
      contentTextStyle: const TextStyle(fontSize: 14, color: kTextSecondary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccentAmber,
        foregroundColor: kBgTop,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kTextSecondary),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kTextSecondary,
        side: BorderSide(color: kGlassBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kGlassFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kGlassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kGlassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kAccentAmber, width: 1.5),
      ),
      labelStyle: const TextStyle(color: kTextMuted),
      hintStyle: const TextStyle(color: kTextMuted),
      prefixIconColor: kTextMuted,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kGlassFill,
      side: const BorderSide(color: kGlassBorder),
      labelStyle: const TextStyle(fontSize: 13, color: kTextPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kAccentAmber,
    ),
  );
}

// ── Centered toast overlay ──

/// Shows a centered, auto-dismissing glass toast instead of a bottom SnackBar.
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
    final accent = widget.color ?? kAccentAmber;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: _opacity,
            builder: (ctx, child) => Opacity(opacity: _opacity.value, child: child),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xE6181c2a),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withAlpha(60), width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: accent.withAlpha(40),
                    blurRadius: 24,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

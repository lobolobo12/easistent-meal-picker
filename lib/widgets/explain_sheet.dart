import 'package:flutter/material.dart';

import '../services/meal_predictor.dart';
import '../theme.dart';

/// Shows why the model scored an option the way it did.
///
/// The predictor surfaced a single number and a highlighted card. When it
/// picked something odd there was no way to tell whether it had misread the
/// food, was coasting on a menu habit, or was acting on a keyword set months
/// ago and forgotten — so the only available responses were to trust it or
/// to override it blindly. This shows the same arithmetic the score came
/// from, which is also the fastest route to the setting worth changing.
Future<void> showExplainSheet(
  BuildContext context, {
  required String menuName,
  required String description,
  required PickExplanation explanation,
  required bool isAiPick,
  String? closeRunnerUp,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder:
        (_) => _ExplainSheet(
          menuName: menuName,
          description: description,
          explanation: explanation,
          isAiPick: isAiPick,
          closeRunnerUp: closeRunnerUp,
        ),
  );
}

class _ExplainSheet extends StatelessWidget {
  final String menuName;
  final String description;
  final PickExplanation explanation;
  final bool isAiPick;

  /// Set when this pick only just beat another option, naming it.
  final String? closeRunnerUp;

  const _ExplainSheet({
    required this.menuName,
    required this.description,
    required this.explanation,
    required this.isAiPick,
    required this.closeRunnerUp,
  });

  @override
  Widget build(BuildContext context) {
    final accent = menuColor(menuName);
    // Scale the bars against the strongest factor so a near-zero signal
    // does not render as a misleadingly long bar.
    final widest = explanation.factors
        .map((f) => f.contribution.abs())
        .fold<double>(0.01, (a, b) => b > a ? b : a);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(kSp8),
        child: GlassSheet(
          radius: kRadiusCard + 6,
          padding: const EdgeInsets.fromLTRB(kSp16, kSp12, kSp16, kSp16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: kSp12),
                  decoration: BoxDecoration(
                    color: kTextMuted.withAlpha(90),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      menuName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: kTextPrimary,
                      ),
                    ),
                  ),
                  if (isAiPick)
                    PillChip(
                      label: closeRunnerUp != null ? 'AI · tesno' : 'Izbira AI',
                      color:
                          closeRunnerUp != null
                              ? kTextMuted
                              : kAccentMauve.withAlpha(200),
                    ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: kSp4),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: kTextSecondary),
                ),
              ],
              const SizedBox(height: kSp12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    explanation.total >= 0
                        ? '+${explanation.total.toStringAsFixed(2)}'
                        : explanation.total.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: explanation.total >= 0 ? accent : kAccentRed,
                    ),
                  ),
                  const SizedBox(width: kSp8),
                  const Text(
                    'skupna ocena',
                    style: TextStyle(fontSize: 13, color: kTextMuted),
                  ),
                ],
              ),
              if (closeRunnerUp != null) ...[
                const SizedBox(height: kSp8),
                Text(
                  'Komaj boljša izbira od: $closeRunnerUp. '
                  'Če ti ta teden ne ustreza, kar zamenjaj.',
                  style: kCaption,
                ),
              ],
              const SizedBox(height: kSp12),
              for (final f in explanation.factors)
                _FactorRow(factor: f, widest: widest),
              const SizedBox(height: kSp12),
              _MaturityNote(maturity: explanation.keywordMaturity),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactorRow extends StatelessWidget {
  final ScoreFactor factor;
  final double widest;

  const _FactorRow({required this.factor, required this.widest});

  @override
  Widget build(BuildContext context) {
    final positive = factor.contribution >= 0;
    final color = positive ? kAccentGreen : kAccentRed;
    final fraction = (factor.contribution.abs() / widest).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: kSp12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  factor.kind.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTextPrimary,
                  ),
                ),
              ),
              Text(
                positive
                    ? '+${factor.contribution.toStringAsFixed(2)}'
                    : factor.contribution.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: factor.contribution.abs() < 0.005 ? kTextMuted : color,
                ),
              ),
            ],
          ),
          const SizedBox(height: kSp4),
          // Bars grow from the centre so a negative factor reads as pulling
          // the score down rather than as a smaller positive one.
          LayoutBuilder(
            builder: (context, c) {
              final half = c.maxWidth / 2;
              return SizedBox(
                height: 4,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: kGlassBottom,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Positioned(
                      left: positive ? half : half - half * fraction,
                      width: half * fraction,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withAlpha(200),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (factor.terms.isNotEmpty) ...[
            const SizedBox(height: kSp8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (word, weight) in factor.terms)
                  _TermChip(word: word, positive: weight >= 0),
              ],
            ),
          ] else if (factor.note.isNotEmpty) ...[
            const SizedBox(height: kSp4),
            Text(factor.note, style: kCaption),
          ],
        ],
      ),
    );
  }
}

class _TermChip extends StatelessWidget {
  final String word;
  final bool positive;

  const _TermChip({required this.word, required this.positive});

  @override
  Widget build(BuildContext context) {
    final color = positive ? kAccentGreen : kAccentRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        word,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// How much the model actually knows yet, said plainly.
class _MaturityNote extends StatelessWidget {
  final double maturity;

  const _MaturityNote({required this.maturity});

  @override
  Widget build(BuildContext context) {
    final pct = (maturity * 100).round();
    final text =
        maturity < 0.25
            ? 'Model ima še malo podatkov, zato se bolj zanaša na to, kateri meni '
                'običajno izbereš. Sestavine štejejo $pct % svoje končne teže — '
                'z vsakim tednom več.'
            : 'Sestavine štejejo $pct % svoje končne teže.';

    return Container(
      padding: const EdgeInsets.all(kSp12),
      decoration: BoxDecoration(
        color: kGlassBottom,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kGlassEdge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: kTextMuted),
          const SizedBox(width: kSp8),
          Expanded(child: Text(text, style: kCaption)),
        ],
      ),
    );
  }
}

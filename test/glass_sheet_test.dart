import 'dart:ui';

import 'package:easistent_meal_picker/services/meal_predictor.dart';
import 'package:easistent_meal_picker/theme.dart';
import 'package:easistent_meal_picker/widgets/explain_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bug these guard: a modal surface that is translucent but has no
/// BackdropFilter. The bed behind the app is deliberately colourful, so
/// whatever is underneath reads straight through the text.
void main() {
  group('GlassSheet', () {
    testWidgets('actually blurs what is behind it', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: GlassSheet(child: Text('vsebina')),
      ));

      final filter = tester.widget<BackdropFilter>(
          find.descendant(
              of: find.byType(GlassSheet),
              matching: find.byType(BackdropFilter)));
      expect(filter.filter, isA<ImageFilter>());
    });

    testWidgets('sits on an opaque enough base to read white text on',
        (tester) async {
      // A thin white fill over the coloured bed was the original failure:
      // it lightened the background without hiding it.
      expect(kSheetBase.a, greaterThan(0.9));

      await tester.pumpWidget(const MaterialApp(
        home: GlassSheet(child: Text('vsebina')),
      ));
      expect(find.text('vsebina'), findsOneWidget);
    });

    testWidgets('clips its blur to the rounded corners', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: GlassSheet(child: Text('vsebina')),
      ));
      expect(
        find.ancestor(
            of: find.byType(BackdropFilter),
            matching: find.byType(ClipRRect)),
        findsWidgets,
      );
    });
  });

  group('the explanation sheet', () {
    testWidgets('is built on GlassSheet, so it blurs', (tester) async {
      final model = MealPredictor.fromData(
          trainingData: const [], preferences: const {});

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showExplainSheet(
                  context,
                  menuName: 'Meni 5',
                  description: 'pica margarita',
                  explanation: model.explain('Meni 5', 'pica margarita'),
                  isAiPick: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(GlassSheet), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(GlassSheet),
            matching: find.byType(BackdropFilter)),
        findsOneWidget,
      );
    });
  });

  group('dialogs', () {
    testWidgets('AlertDialog is opaque, since it cannot carry a blur',
        (tester) async {
      // AlertDialog gives no hook for a BackdropFilter, so the theme has to
      // compensate with opacity. Unreadable is worse than un-glassy.
      final theme = buildAppTheme();
      final bg = theme.dialogTheme.backgroundColor!;
      expect(bg.a, greaterThan(0.9),
          reason: 'dialog background must not be a thin translucent fill');
    });
  });
}

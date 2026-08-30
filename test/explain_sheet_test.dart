import 'package:easistent_meal_picker/services/meal_predictor.dart';
import 'package:easistent_meal_picker/widgets/explain_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final model = MealPredictor.fromData(
    trainingData: [
      for (var i = 0; i < 3; i++)
        {
          'date': '2026-05-0${i + 1}',
          'options': [
            {
              'menu_id': '101',
              'menu_name': 'Meni 1',
              'description': 'ricet s klobaso',
              'chosen': false,
            },
            {
              'menu_id': '105',
              'menu_name': 'Meni 5 (XXL +0,70€)',
              'description': 'pica margarita',
              'chosen': true,
            },
          ],
        }
    ],
    preferences: const {
      'liked_keywords': ['pica'],
      'disliked_keywords': ['ricet'],
    },
  );

  Future<void> open(WidgetTester tester, String menu, String desc) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showExplainSheet(
                context,
                menuName: menu,
                description: desc,
                explanation: model.explain(menu, desc),
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
  }

  testWidgets('renders the option and every signal', (tester) async {
    await open(tester, 'Meni 5 (XXL +0,70€)', 'pica margarita');

    expect(find.text('Meni 5 (XXL +0,70€)'), findsOneWidget);
    expect(find.text('pica margarita'), findsOneWidget);
    expect(find.text('Izbira AI'), findsOneWidget);

    for (final kind in FactorKind.values) {
      expect(find.text(kind.label), findsOneWidget,
          reason: 'missing factor row for ${kind.name}');
    }
  });

  testWidgets('the displayed total matches the model', (tester) async {
    const menu = 'Meni 5 (XXL +0,70€)';
    const desc = 'pica margarita';
    await open(tester, menu, desc);

    final total = model.scoreOption(menu, desc);
    final shown =
        '${total >= 0 ? '+' : ''}${total.toStringAsFixed(2)}';
    expect(find.text(shown), findsOneWidget);
    expect(find.text('skupna ocena'), findsOneWidget);
  });

  testWidgets('shows the words driving a match', (tester) async {
    await open(tester, 'Meni 1', 'ricet s klobaso');
    // "ricet" is an explicit dislike, so it must be named.
    expect(find.text('ricet'), findsWidgets);
  });

  testWidgets('says the model is still learning when data is thin',
      (tester) async {
    await open(tester, 'Meni 5 (XXL +0,70€)', 'pica margarita');
    expect(
      find.textContaining('Model ima še malo podatkov'),
      findsOneWidget,
    );
  });

  testWidgets('an unknown dish still renders without throwing',
      (tester) async {
    await open(tester, 'Meni 9', 'popolnoma neznana jed');
    expect(find.text('Meni 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

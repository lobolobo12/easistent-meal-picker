import 'package:easistent_meal_picker/models/meal_option.dart';
import 'package:easistent_meal_picker/services/meal_predictor.dart';
import 'package:flutter_test/flutter_test.dart';

MealOption o(String id, String name, String desc, {String status = 'available'}) =>
    MealOption(
      menuId: id,
      menuName: name,
      description: desc,
      status: status,
      locationId: '1',
      mealType: 'malica',
    );

void main() {
  /// A model with one clear favourite menu.
  final model = MealPredictor.fromData(
    trainingData: [
      for (var i = 0; i < 6; i++)
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
              'menu_name': 'Meni 5',
              'description': 'pica margarita',
              'chosen': true,
            },
          ],
        }
    ],
    preferences: const {},
  );

  group('rankDay', () {
    test('names the winner and the runner-up', () {
      final r = model.rankDay([
        o('101', 'Meni 1', 'ricet s klobaso'),
        o('105', 'Meni 5', 'pica margarita'),
      ]);
      expect(r.menuId, '105');
      expect(r.runnerUpId, '101');
      expect(r.runnerUpName, 'Meni 1');
    });

    test('a clear favourite is not flagged as close', () {
      final r = model.rankDay([
        o('101', 'Meni 1', 'ricet s klobaso'),
        o('105', 'Meni 5', 'pica margarita'),
      ]);
      expect(r.isClose, isFalse);
      expect(r.relativeMargin, greaterThan(DayRanking.closeThreshold));
    });

    test('two identical options are a tie', () {
      // Same menu identity and same words: nothing separates them, so the
      // badge must not claim a decision was made.
      final r = model.rankDay([
        o('105', 'Meni 5', 'pica margarita'),
        o('106', 'Meni 5', 'pica margarita'),
      ]);
      expect(r.isClose, isTrue);
      expect(r.relativeMargin, 0);
    });

    test('a single candidate is decisive by default', () {
      final r = model.rankDay([o('105', 'Meni 5', 'pica margarita')]);
      expect(r.menuId, '105');
      expect(r.isClose, isFalse);
      expect(r.runnerUpId, isNull);
    });

    test('reports nothing when no option is selectable', () {
      final r = model.rankDay([
        o('105', 'Meni 5', 'pica', status: 'cancelled'),
      ]);
      expect(r.menuId, isNull);
      expect(r.isClose, isFalse);
    });

    test('ordered options are excluded by default', () {
      // The unattended submit must not overwrite a real choice.
      final r = model.rankDay([
        o('101', 'Meni 1', 'ricet s klobaso'),
        o('105', 'Meni 5', 'pica margarita', status: 'ordered'),
      ]);
      expect(r.menuId, '101');
    });

    test('but the caller can widen what counts as a candidate', () {
      // Which is what the menu screen does, so its highlight and its
      // closeness flag describe the same set of options.
      final r = model.rankDay(
        [
          o('101', 'Meni 1', 'ricet s klobaso'),
          o('105', 'Meni 5', 'pica margarita', status: 'ordered'),
        ],
        isCandidate: (x) => x.status == 'available' || x.status == 'ordered',
      );
      expect(r.menuId, '105');
    });

    test('agrees with pickBest on the same candidate set', () {
      final options = [
        o('101', 'Meni 1', 'ricet s klobaso'),
        o('105', 'Meni 5', 'pica margarita'),
      ];
      expect(model.rankDay(options).menuId, model.pickBest(options));
    });
  });
}

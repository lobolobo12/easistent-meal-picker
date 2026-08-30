import 'package:easistent_meal_picker/models/meal_option.dart';
import 'package:easistent_meal_picker/services/meal_predictor.dart';
import 'package:easistent_meal_picker/services/training_store.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> day(String date, String chosenMenu, {int? weight}) => {
      'date': date,
      'options': [
        {
          'menu_id': '101',
          'menu_name': 'Meni 1',
          'description': 'ricet s klobaso',
          'chosen': chosenMenu == 'Meni 1',
        },
        {
          'menu_id': '105',
          'menu_name': 'Meni 5',
          'description': 'pica margarita',
          'chosen': chosenMenu == 'Meni 5',
        },
      ],
      if (weight != null) 'weight': weight,
    };

void main() {
  group('collapseDuplicates', () {
    test('folds repeated rows into a weight', () {
      final tripled = [
        for (var i = 0; i < 3; i++) day('2026-05-01', 'Meni 5'),
      ];
      final collapsed = TrainingStore.collapseDuplicates(tripled);

      expect(collapsed, hasLength(1));
      expect(collapsed.single['weight'], 3);
    });

    test('leaves a single day without a weight key', () {
      final collapsed =
          TrainingStore.collapseDuplicates([day('2026-05-01', 'Meni 5')]);
      expect(collapsed.single.containsKey('weight'), isFalse);
    });

    test('keeps distinct days apart and preserves order', () {
      final collapsed = TrainingStore.collapseDuplicates([
        day('2026-05-01', 'Meni 5'),
        day('2026-05-02', 'Meni 1'),
        day('2026-05-01', 'Meni 5'),
      ]);
      expect(collapsed, hasLength(2));
      expect(collapsed.first['date'], '2026-05-01');
      expect(collapsed.first['weight'], 2);
      expect(collapsed.last['date'], '2026-05-02');
    });

    test('is idempotent', () {
      final once = TrainingStore.collapseDuplicates(
          [for (var i = 0; i < 3; i++) day('2026-05-01', 'Meni 5')]);
      expect(TrainingStore.collapseDuplicates(once), once);
    });

    test('sums existing weights rather than discarding them', () {
      final collapsed = TrainingStore.collapseDuplicates([
        day('2026-05-01', 'Meni 5', weight: 3),
        day('2026-05-01', 'Meni 5'),
      ]);
      expect(collapsed.single['weight'], 4);
    });
  });

  group('the model reads weights', () {
    List<MealOption> options() => [
          MealOption(
              menuId: '101',
              menuName: 'Meni 1',
              description: 'ricet s klobaso',
              status: 'available',
              locationId: '1',
              mealType: 'malica'),
          MealOption(
              menuId: '105',
              menuName: 'Meni 5',
              description: 'pica margarita',
              status: 'available',
              locationId: '1',
              mealType: 'malica'),
        ];

    test('a weighted day outvotes an equal number of unweighted ones', () {
      // Two plain days for Meni 1, one heavily weighted day for Meni 5.
      final model = MealPredictor.fromData(
        trainingData: [
          day('2026-05-01', 'Meni 1'),
          day('2026-05-02', 'Meni 1'),
          day('2026-05-03', 'Meni 5', weight: 6),
        ],
        preferences: const {},
      );
      expect(model.pickBest(options()), '105');
    });

    test('collapsing preserves the learned rates exactly', () {
      // With the frequency floor out of the way, folding three identical
      // rows into weight:3 must be arithmetically invisible — that is what
      // makes the migration safe.
      const noFloor = PredictorTuning(minTokenFreq: 1, shrinkageK: 0);
      final tripled = [
        for (var i = 0; i < 3; i++) day('2026-05-01', 'Meni 5'),
        day('2026-05-02', 'Meni 1'),
      ];
      final collapsed = TrainingStore.collapseDuplicates(tripled);

      final a = MealPredictor.fromData(
          trainingData: tripled, preferences: const {}, tuning: noFloor);
      final b = MealPredictor.fromData(
          trainingData: collapsed, preferences: const {}, tuning: noFloor);

      for (final o in options()) {
        expect(b.scoreOption(o.menuName, o.description),
            closeTo(a.scoreOption(o.menuName, o.description), 1e-9),
            reason: 'collapsing moved the rate for ${o.menuName}');
      }
    });

    test('collapsing does change what clears the frequency floor', () {
      // And this is the point of the change, not a side effect. Three copies
      // of one day used to make every word in it look three times as
      // familiar as it was, letting a manually submitted day past a floor an
      // identical scraped day could not clear.
      final tripled = [
        for (var i = 0; i < 3; i++) day('2026-05-01', 'Meni 5'),
      ];
      final collapsed = TrainingStore.collapseDuplicates(tripled);

      final before = MealPredictor.fromData(
          trainingData: tripled, preferences: const {});
      final after = MealPredictor.fromData(
          trainingData: collapsed, preferences: const {});

      expect(before.vocabularySize, greaterThan(0));
      expect(after.vocabularySize, 0);
    });

    test('the frequency floor counts sightings, not weight', () {
      // A single day weighted 10x has still only been seen once, so its
      // words must not slip past a floor a scraped day could not clear.
      final heavy = MealPredictor.fromData(
        trainingData: [day('2026-05-01', 'Meni 5', weight: 10)],
        preferences: const {},
      );
      expect(heavy.vocabularySize, 0);
    });

    test('a malformed weight falls back to 1 instead of throwing', () {
      expect(
        () => MealPredictor.fromData(
          trainingData: [
            {...day('2026-05-01', 'Meni 5'), 'weight': 'heavy'}
          ],
          preferences: const {},
        ).pickBest(options()),
        returnsNormally,
      );
    });
  });
}

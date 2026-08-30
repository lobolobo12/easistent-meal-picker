import 'package:easistent_meal_picker/services/meal_predictor.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> lastYear(String date) => {
      'date': date,
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
    };

void main() {
  final model = MealPredictor.fromData(
    trainingData: [lastYear('2026-05-01'), lastYear('2026-05-02')],
    preferences: const {},
  );

  group('knownMenus', () {
    test('lists the menus the model has history for', () {
      expect(model.knownMenus, {'Meni 1', 'Meni 5'});
    });

    test('a price change keeps the menu recognised across a school year', () {
      // The school rewrote "(XXL +0,70€)" as "(XXL+0,80 EUR)" over one
      // summer. That must not read as a brand new menu.
      expect(model.knownMenus.contains(normalizeMenuName('Meni 5 (XXL+0,80 EUR)')),
          isTrue);
    });

    test('a genuinely new menu is not recognised', () {
      expect(model.knownMenus.contains(normalizeMenuName('Meni 9 (nov)')),
          isFalse);
    });

    test('an untrained model claims to know nothing', () {
      // So the banner stays quiet on a fresh install, where onboarding is
      // already asking for the same thing.
      final fresh = MealPredictor.fromData(
          trainingData: const [], preferences: const {});
      expect(fresh.knownMenus, isEmpty);
    });
  });
}

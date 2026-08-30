import 'package:easistent_meal_picker/services/easistent_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/meal_week.dart';

void main() {
  // Parsing is pure and needs no session, so a throwaway client is fine.
  final client = EAsistentClient(username: 'u', password: 'p');

  group('parseMealTable', () {
    final menu = client.parseMealTable(kMealWeekHtml);

    test('reads every cell for a day', () {
      expect(menu['2025-09-01'], hasLength(2));
      expect(menu['2025-09-02'], hasLength(3));
    });

    test('keys the map by the dates in the day headers', () {
      expect(menu.keys.toSet(), {'2025-09-01', '2025-09-02'});
    });

    test('drops cells for dates outside the rendered week', () {
      // The 2025-09-08 cell has no matching day header. Keeping it would
      // put a stray day on the menu screen.
      expect(menu.containsKey('2025-09-08'), isFalse);
    });

    test('reads menu id, name, description and location', () {
      final monday = menu['2025-09-01']!;
      expect(monday, hasLength(2));

      final meni1 = monday.firstWhere((o) => o.menuId == '101');
      expect(meni1.menuName, 'Meni 1');
      expect(meni1.description, 'Piščančji zrezek, pire krompir (mleko)');
      expect(meni1.locationId, '15856');
      expect(meni1.mealType, 'malica');
    });

    test('maps the three status markers', () {
      final monday = menu['2025-09-01']!;
      expect(monday.firstWhere((o) => o.menuId == '101').status, 'ordered');
      expect(monday.firstWhere((o) => o.menuId == '102').status, 'available');

      final tuesday = menu['2025-09-02']!;
      // span.error "Odjavljen" and no action div.
      expect(tuesday.firstWhere((o) => o.menuId == '101').status, 'cancelled');
      // Neither marker present.
      expect(tuesday.firstWhere((o) => o.menuId == '102').status, 'none');
    });

    test('keeps the bracketed price suffix in the display name', () {
      // normalizeMenuName strips it for model keys; the raw name must
      // survive here so the UI can still show what the school calls it.
      final monday = menu['2025-09-01']!;
      expect(monday.firstWhere((o) => o.menuId == '102').menuName,
          'Meni 5 (XXL+0,80 EUR)');
    });

    test('returns an empty map for HTML with no meal table', () {
      expect(client.parseMealTable('<html><body>Ni podatkov</body></html>'),
          isEmpty);
    });
  });

  group('findCurrentWeek', () {
    test('reads the selected option', () {
      expect(client.findCurrentWeek(kWeekSelectHtml), 36);
    });

    test('returns null when the selector is absent', () {
      expect(client.findCurrentWeek('<html></html>'), isNull);
    });

    test('ignores a selected option outside the week selector', () {
      // Another select on the page must not be mistaken for the week one.
      const other =
          '<select id="something-else"><option value="99" selected="selected">x</option></select>';
      expect(client.findCurrentWeek(other), isNull);
    });
  });
}

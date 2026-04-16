import 'package:flutter_test/flutter_test.dart';

import 'package:easistent_meal_picker/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MealPickerApp());
    expect(find.text('Meni'), findsWidgets);
  });
}

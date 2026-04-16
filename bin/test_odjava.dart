// ignore_for_file: avoid_print, avoid_relative_lib_imports
import '../lib/models/meal_option.dart';
import '../lib/services/meal_predictor.dart';

void main() {
  // Synthetic training: six historical days where "piščanc/riba/klobasa"
  // were consistently rejected and "sir/zelenjava" was chosen. Crosses
  // the _minTokenFreq=3 gate so tokens get scored.
  final training = <dynamic>[
    for (var i = 0; i < 6; i++)
      {
        'date': '2025-01-$i',
        'options': [
          {
            'menu_name': 'Meni 1',
            'menu_id': '1',
            'description': 'piščanc riba klobasa',
            'chosen': false,
          },
          {
            'menu_name': 'Meni 2',
            'menu_id': '2',
            'description': 'piščanc riba klobasa',
            'chosen': false,
          },
          {
            'menu_name': 'Meni 3',
            'menu_id': '3',
            'description': 'sir zelenjava solata',
            'chosen': true,
          },
        ],
      },
  ];

  final pred = MealPredictor.fromData(
    trainingData: training,
    preferences: {'disliked_keywords': ['piščanc', 'riba', 'klobasa']},
  );

  // All-bad day — every available option matches disliked keywords.
  final allBad = [
    const MealOption(
        menuId: '1',
        menuName: 'Meni 1',
        description: 'piščanc riba klobasa',
        status: 'available',
        locationId: '0'),
    const MealOption(
        menuId: '2',
        menuName: 'Meni 2',
        description: 'piščanc riba klobasa',
        status: 'available',
        locationId: '0'),
    const MealOption(
        menuId: '3',
        menuName: 'Meni 3',
        description: 'piščanc riba klobasa',
        status: 'available',
        locationId: '0'),
  ];
  final r1 = pred.pickBestOrOdjava(allBad);
  print(
      'all-bad  => recommendOdjava=${r1.recommendOdjava} bestScore=${r1.bestScore?.toStringAsFixed(2)} menuId=${r1.menuId}');
  if (!r1.recommendOdjava) {
    throw StateError('Expected Odjava for all-strongly-negative day');
  }

  // Mixed day — one neutral/positive option.
  final mixed = [
    const MealOption(
        menuId: '1',
        menuName: 'Meni 1',
        description: 'piščanc riba',
        status: 'available',
        locationId: '0'),
    const MealOption(
        menuId: '3',
        menuName: 'Meni 3',
        description: 'sir zelenjava solata',
        status: 'available',
        locationId: '0'),
  ];
  final r2 = pred.pickBestOrOdjava(mixed);
  print(
      'mixed    => recommendOdjava=${r2.recommendOdjava} bestScore=${r2.bestScore?.toStringAsFixed(2)} menuId=${r2.menuId}');
  if (r2.recommendOdjava) {
    throw StateError('Expected menu pick when a positive option exists');
  }

  // Nothing available.
  final none = [
    const MealOption(
        menuId: '1',
        menuName: 'Meni 1',
        description: 'anything',
        status: 'locked',
        locationId: '0'),
  ];
  final r3 = pred.pickBestOrOdjava(none);
  print(
      'no-avail => recommendOdjava=${r3.recommendOdjava} menuId=${r3.menuId}');
  if (r3.menuId != null || r3.recommendOdjava) {
    throw StateError('Expected none when nothing is available');
  }

  print('');
  print('All Odjava-fallback assertions passed.');
  print('Threshold in use: $kOdjavaScoreThreshold');
}

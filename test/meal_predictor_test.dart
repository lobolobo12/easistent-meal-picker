import 'package:easistent_meal_picker/models/meal_option.dart';
import 'package:easistent_meal_picker/services/meal_predictor.dart';
import 'package:flutter_test/flutter_test.dart';

MealOption opt(String id, String name, String desc,
        {String status = 'available'}) =>
    MealOption(
      menuId: id,
      menuName: name,
      description: desc,
      status: status,
      locationId: '15856',
      mealType: 'malica',
    );

Map<String, dynamic> day(List<(String, String, String, bool)> options) => {
      'date': '2025-09-01',
      'options': [
        for (final (id, name, desc, chosen) in options)
          {
            'menu_id': id,
            'menu_name': name,
            'description': desc,
            'chosen': chosen,
          }
      ],
    };

void main() {
  group('tokenize', () {
    test('lowercases and keeps Slovenian letters', () {
      expect(tokenize('Piščančji Zrezek'), ['piščančji', 'zrezek']);
    });

    test('strips allergen parentheticals', () {
      // The allergen list is boilerplate on every option; leaving it in
      // would make every description look alike to the model.
      expect(tokenize('kruh (pšenica, mlečni izdelek)'), ['kruh']);
    });

    test('but keeps a bracket that lists real ingredients', () {
      // Not every bracket is allergens. This one is the dish itself, and
      // discarding it threw away five vegetables the model could learn from.
      expect(
        tokenize('solata (paradižnik, paprika, fižol)'),
        containsAll(['paradižnik', 'paprika', 'fižol']),
      );
    });

    test('drops stop words and tokens under three characters', () {
      expect(tokenize('juha z rižem in sok'), ['juha', 'rižem']);
    });
  });

  group('normalizeMenuName', () {
    test('drops the bracketed suffix so a renamed menu keeps its history', () {
      // The school renamed this over the summer; both must key the same.
      expect(normalizeMenuName('Meni 5 (XXL +0,70€)'), 'Meni 5');
      expect(normalizeMenuName('Meni 5 (XXL+0,80 EUR)'), 'Meni 5');
    });

    test('collapses internal whitespace', () {
      expect(normalizeMenuName('Meni   3   (veg)'), 'Meni 3');
    });

    test('falls back to the raw name when the bracket leads', () {
      expect(normalizeMenuName('(veg)'), '(veg)');
    });
  });

  group('scoreOption', () {
    test('a menu renamed mid-year scores identically to its old label', () {
      final model = MealPredictor.fromData(
        trainingData: [
          day([
            ('1', 'Meni 1', 'juha', false),
            ('2', 'Meni 5 (XXL +0,70€)', 'pica', true),
          ]),
        ],
        preferences: const {},
      );
      expect(
        model.scoreOption('Meni 5 (XXL+0,80 EUR)', 'pica'),
        model.scoreOption('Meni 5 (XXL +0,70€)', 'pica'),
      );
    });

    test('explicit disliked keywords push a score down', () {
      final model = MealPredictor.fromData(
        trainingData: const [],
        preferences: const {
          'disliked_keywords': ['ričet']
        },
      );
      expect(model.scoreOption('Meni 1', 'ričet s klobaso'),
          lessThan(model.scoreOption('Meni 1', 'pica margarita')));
    });
  });

  group('rating shrinkage', () {
    // A single rating used to give every token in its description the full
    // weight, so one 5-star bread roll promoted every meal with "kruh".
    List<Map<String, dynamic>> ratings(int n) => [
          for (var i = 0; i < n; i++)
            {
              'date': '2025-09-0${i + 1}',
              'description': 'kruh in maslo',
              'rating': 5,
            }
        ];

    double scoreWith(List<Map<String, dynamic>> r, PredictorTuning t) =>
        MealPredictor.fromData(
          trainingData: const [],
          preferences: const {},
          ratings: r,
          tuning: t,
        ).scoreOption('Meni 1', 'kruh in maslo');

    test('one rating carries less weight than the legacy model gave it', () {
      expect(scoreWith(ratings(1), PredictorTuning.current),
          lessThan(scoreWith(ratings(1), PredictorTuning.legacy)));
    });

    test('influence grows as ratings accumulate', () {
      final one = scoreWith(ratings(1), PredictorTuning.current);
      final four = scoreWith(ratings(4), PredictorTuning.current);
      expect(four, greaterThan(one));
    });

    test('never exceeds the unshrunk score', () {
      expect(scoreWith(ratings(50), PredictorTuning.current),
          lessThanOrEqualTo(scoreWith(ratings(50), PredictorTuning.legacy)));
    });

    test('a non-integer rating falls back to neutral instead of throwing', () {
      // Stored ratings are ints, but a hand-edited file could hold a string.
      expect(
        () => MealPredictor.fromData(
          trainingData: const [],
          preferences: const {},
          ratings: [
            {'date': '2025-09-01', 'description': 'kruh', 'rating': 'five'}
          ],
        ).scoreOption('Meni 1', 'kruh'),
        returnsNormally,
      );
    });
  });

  group('pickBest', () {
    final model = MealPredictor.fromData(
      trainingData: [
        day([
          ('1', 'Meni 1', 'ričet s klobaso', false),
          ('2', 'Meni 2', 'pica margarita', true),
        ]),
        day([
          ('1', 'Meni 1', 'ričet z zeljem', false),
          ('2', 'Meni 2', 'pica s šunko', true),
        ]),
      ],
      preferences: const {},
    );

    test('returns the highest scoring available option', () {
      final pick = model.pickBest([
        opt('1', 'Meni 1', 'ričet s klobaso'),
        opt('2', 'Meni 2', 'pica margarita'),
      ]);
      expect(pick, '2');
    });

    test('skips options that are not available', () {
      // An already-ordered day must not be overwritten by auto-submit.
      final pick = model.pickBest([
        opt('1', 'Meni 1', 'ričet s klobaso'),
        opt('2', 'Meni 2', 'pica margarita', status: 'ordered'),
      ]);
      expect(pick, '1');
    });

    test('returns null when nothing is available', () {
      expect(
        model.pickBest([opt('1', 'Meni 1', 'karkoli', status: 'cancelled')]),
        isNull,
      );
    });

    test('agrees with pickBestOrOdjava on the same input', () {
      // The two used to carry separate copies of this scan and could drift.
      final options = [
        opt('1', 'Meni 1', 'ričet s klobaso'),
        opt('2', 'Meni 2', 'pica margarita'),
      ];
      expect(model.pickBest(options),
          model.pickBestOrOdjava(options).menuId);
    });
  });

  group('pickBestOrOdjava', () {
    test('recommends Odjava when every option is strongly negative', () {
      final model = MealPredictor.fromData(
        trainingData: const [],
        preferences: const {
          'disliked_keywords': ['ričet', 'klobasa']
        },
      );
      final result = model.pickBestOrOdjava([
        opt('1', 'Meni 1', 'ričet in klobasa'),
      ]);
      expect(result.recommendOdjava, isTrue);
      expect(result.menuId, isNull);
    });

    test('picks a menu when one scores above the threshold', () {
      final model = MealPredictor.fromData(
        trainingData: const [],
        preferences: const {
          'liked_keywords': ['pica']
        },
      );
      final result = model.pickBestOrOdjava([
        opt('1', 'Meni 1', 'pica margarita'),
      ]);
      expect(result.recommendOdjava, isFalse);
      expect(result.menuId, '1');
    });

    test('reports none when there is nothing to score', () {
      final model = MealPredictor.fromData(
        trainingData: const [],
        preferences: const {},
      );
      final result = model.pickBestOrOdjava(
          [opt('1', 'Meni 1', 'karkoli', status: 'ordered')]);
      expect(result.menuId, isNull);
      expect(result.recommendOdjava, isFalse);
    });
  });

  group('tuning', () {
    test('the token model itself is unchanged from legacy', () {
      // Walk-forward evaluation could not justify changing how tokens are
      // counted, so the frequency floor and shrinkage stay where they were.
      // What did change is how much the keyword signal is allowed to matter.
      expect(PredictorTuning.current.minTokenFreq,
          PredictorTuning.legacy.minTokenFreq);
      expect(PredictorTuning.current.shrinkageK,
          PredictorTuning.legacy.shrinkageK);
    });

    test('the keyword signal is evidence-scaled and menu weight leads', () {
      expect(PredictorTuning.current.keywordEvidenceK, greaterThan(0));
      expect(PredictorTuning.legacy.keywordEvidenceK, 0);
      expect(PredictorTuning.current.wMenuType,
          greaterThan(PredictorTuning.legacy.wMenuType));
    });
  });

  group('a consistent menu preference must survive misleading keywords', () {
    // The regression this locks down. Measured on the real training data the
    // predictor scored 3/6 where "just pick the usual menu" scored 5/6 — the
    // model was worse than having no model. The cause was the weighting: the
    // keyword signal carried the largest weight (1.0) while being built from
    // a handful of days, and it overrode a menu preference held 86% of the
    // time (weighted 0.3).
    //
    // Reproduced here: the user picks Meni 5 nine days out of ten, and those
    // meals nearly always contain "pica". Then a day arrives where the pica
    // is on Meni 1 instead. The keyword signal says take the pica; the menu
    // signal says the user always takes Meni 5. The user takes Meni 5.
    List<Map<String, dynamic>> history() => [
          for (var i = 0; i < 10; i++)
            {
              'date': '2026-05-${(i + 1).toString().padLeft(2, '0')}',
              'options': [
                {
                  'menu_id': '101',
                  'menu_name': 'Meni 1',
                  'description': 'ricet s klobaso',
                  'chosen': i == 3,
                },
                {
                  'menu_id': '105',
                  'menu_name': 'Meni 5 (XXL +0,70€)',
                  'description': 'pica margarita',
                  'chosen': i != 3,
                },
              ],
            }
        ];

    // The pica has moved to Meni 1 today.
    final today = [
      opt('101', 'Meni 1', 'pica margarita'),
      opt('105', 'Meni 5 (XXL+0,80 EUR)', 'ricet s klobaso'),
    ];

    test('the shipped model stays with the usual menu', () {
      final model = MealPredictor.fromData(
        trainingData: history(),
        preferences: const {},
      );
      expect(model.pickBest(today), '105');
    });

    test('the old weighting chased the keyword instead', () {
      // Kept as evidence of the bug, not as a requirement. If a future
      // change makes the legacy tuning pass this too, delete this test
      // rather than "fixing" it.
      final legacyModel = MealPredictor.fromData(
        trainingData: history(),
        preferences: const {},
        tuning: PredictorTuning.legacy,
      );
      expect(legacyModel.pickBest(today), '101');
    });

    test('keywords regain influence once there is enough data to trust them',
        () {
      // Same shape, but 200 days. The evidence scaling should have handed
      // most of the keyword weight back by then.
      final long = [
        for (var i = 0; i < 200; i++)
          {
            'date': '2026-01-01',
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
      ];
      // Distinct dates drive the scaling, so give each day its own date.
      for (var i = 0; i < long.length; i++) {
        long[i]['date'] =
            DateTime(2026, 1, 1).add(Duration(days: i)).toString().split(' ').first;
      }

      final short = MealPredictor.fromData(
          trainingData: history(), preferences: const {});
      final many =
          MealPredictor.fromData(trainingData: long, preferences: const {});

      // The keyword "pica" should pull harder in the well-fed model.
      final shortGap = short.scoreOption('Meni 1', 'pica margarita') -
          short.scoreOption('Meni 1', 'ricet s klobaso');
      final manyGap = many.scoreOption('Meni 1', 'pica margarita') -
          many.scoreOption('Meni 1', 'ricet s klobaso');
      expect(manyGap, greaterThan(shortGap));
    });
  });

  group('explain', () {
    final model = MealPredictor.fromData(
      trainingData: [
        day([
          ('101', 'Meni 1', 'ricet s klobaso', false),
          ('105', 'Meni 5', 'pica margarita', true),
        ]),
        day([
          ('101', 'Meni 1', 'ricet z zeljem', false),
          ('105', 'Meni 5', 'pica s sirom', true),
        ]),
        day([
          ('101', 'Meni 1', 'ricet in kruh', false),
          ('105', 'Meni 5', 'pica funghi', true),
        ]),
      ],
      preferences: const {
        'liked_keywords': ['pica'],
        'disliked_keywords': ['ricet'],
      },
    );

    test('the factors sum to the score the model actually used', () {
      // If these drift apart the breakdown is a plausible-looking fiction,
      // which is worse than showing nothing.
      for (final desc in ['pica margarita', 'ricet s klobaso', 'nekaj cisto novega']) {
        final e = model.explain('Meni 5', desc);
        expect(e.total, closeTo(model.scoreOption('Meni 5', desc), 1e-9),
            reason: 'breakdown must reconcile for "$desc"');
      }
    });

    test('names the words behind a liked match', () {
      final e = model.explain('Meni 5', 'pica margarita');
      final manual =
          e.factors.firstWhere((f) => f.kind == FactorKind.manual);
      expect(manual.terms.map((t) => t.$1), contains('pica'));
      expect(manual.contribution, greaterThan(0));
    });

    test('a disliked word shows as a negative contribution', () {
      final e = model.explain('Meni 1', 'ricet s klobaso');
      final manual =
          e.factors.firstWhere((f) => f.kind == FactorKind.manual);
      expect(manual.contribution, lessThan(0));
    });

    test('factors are ordered by how much they moved the score', () {
      final e = model.explain('Meni 5', 'pica margarita');
      for (var i = 1; i < e.factors.length; i++) {
        expect(e.factors[i - 1].contribution.abs(),
            greaterThanOrEqualTo(e.factors[i].contribution.abs()));
      }
    });

    test('reports how mature the keyword signal is', () {
      // Three days of data is nothing, so the keyword signal should be
      // nowhere near its full influence and the UI can say so.
      final e = model.explain('Meni 5', 'pica margarita');
      expect(e.keywordMaturity, lessThan(0.2));
      expect(e.keywordMaturity, greaterThan(0));
    });

    test('an unseen description still reconciles', () {
      final e = model.explain('Meni 9', 'popolnoma neznana jed');
      expect(e.total, closeTo(model.scoreOption('Meni 9', 'popolnoma neznana jed'), 1e-9));
    });
  });
}

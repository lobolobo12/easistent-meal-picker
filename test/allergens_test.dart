import 'package:easistent_meal_picker/services/health_scorer.dart';
import 'package:easistent_meal_picker/util/allergens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripAllergenDeclarations', () {
    test('drops a standard allergen declaration', () {
      expect(
        stripAllergenDeclarations(
            'bela štručka, maslo in med (pšenica, mlečni izdelek, ki vsebuje laktozo), sok'),
        'bela štručka, maslo in med, sok',
      );
    });

    test('keeps a bracket that lists real ingredients', () {
      // The whole point: the predictor used to discard these five
      // vegetables along with the allergen lists.
      const desc =
          'mehiška solata (paradižnik, paprika, fižol, cvetača, koruza..), kruh';
      expect(stripAllergenDeclarations(desc), desc);
    });

    test('splits a mixed bracket rather than choosing one way for all', () {
      expect(stripAllergenDeclarations('nekaj (pšenica, sir)'),
          'nekaj (sir)');
    });

    test('handles the hyphenated grain-allergen form', () {
      // This school writes "(ječmen-gluten)" and "(pira-gluten)".
      expect(stripAllergenDeclarations('juha (ječmen-gluten)'), 'juha');
      expect(stripAllergenDeclarations('kruh (pira-gluten)'), 'kruh');
    });

    test('handles a traces-of declaration', () {
      expect(
        stripAllergenDeclarations('rogljiček (pšenica, sledi oreščkov)'),
        'rogljiček',
      );
    });

    test('celery is an allergen but green salad is food', () {
      // "zelena" alone is celery; "zelena solata" must survive.
      expect(stripAllergenDeclarations('nekaj (pšenica, zelena)'), 'nekaj');
      expect(stripAllergenDeclarations('nekaj (zelena solata)'),
          'nekaj (zelena solata)');
    });

    test('leaves a description with no brackets alone', () {
      expect(stripAllergenDeclarations('kraška rižota, sok'),
          'kraška rižota, sok');
    });

    test('is safe on an unknown allergen word', () {
      // An allergen term missing from the list keeps its bracket, which is
      // the old behaviour — a miss must never be worse than before.
      expect(stripAllergenDeclarations('nekaj (nekajčisto novega)'),
          'nekaj (nekajčisto novega)');
    });
  });

  group('scoreMeal no longer reads the allergen list as food', () {
    test('two pastries stop earning a protein point for "jajca"', () {
      const pastries =
          'čokoladni navihanček in marelični navihanček (pšenica, mlečni izdelek, ki vsebuje laktozo, jajca), sok';
      // Was 4/10 while the egg allergen counted as protein.
      expect(scoreMeal(pastries).score, 2);
    });

    test('a genuinely nutritious meal keeps its high score', () {
      const salad =
          'polnozrnate testenine v solati s tunino in zelenjavo (pira, pšenica, ribe, mlečni izdelek, ki vsebuje laktozo, jajca, gorčična semena), sadje, sok';
      // Whole grain + vegetable + fruit still score on their own merits,
      // without the allergen bracket propping them up.
      expect(scoreMeal(salad).score, greaterThanOrEqualTo(7));
    });

    test('the vegetables inside an ingredient bracket still count', () {
      const mexican =
          'mehiška solata (paradižnik, paprika, fižol, cvetača, koruza..), kruh (pšenica), sok';
      // Vegetables and a legume are in the bracket; dropping it would have
      // scored this as bare bread.
      expect(scoreMeal(mexican).score, greaterThan(4));
    });
  });

  group('Slovenian case endings the allergen list used to paper over', () {
    // Each of these was only being detected because the word also appeared
    // in the allergen bracket. Removing the bracket exposed the gap, so the
    // keyword list had to grow with it — otherwise the fix would have made
    // the Zdravje tab worse for real food.
    test('"tunino" counts as protein, not just "tuna"', () {
      expect(scoreMeal('testenine s tunino').score,
          greaterThan(scoreMeal('testenine').score));
    });

    test('"jajčni namaz" counts as protein', () {
      // 'jajc' does not match 'jajčni': c and č are different letters.
      expect(scoreMeal('štručka, jajčni namaz').score,
          greaterThan(scoreMeal('štručka').score));
    });

    test('"korenčkom" counts as a vegetable', () {
      expect(scoreMeal('juha s korenčkom').score,
          greaterThan(scoreMeal('juha').score));
    });

    test('ričet is recognised as the legume dish it is', () {
      expect(scoreMeal('ričet').score, greaterThan(scoreMeal('juha').score));
    });
  });
}

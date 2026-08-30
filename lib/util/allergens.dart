/// Separating allergen declarations from real ingredients.
///
/// eAsistent descriptions carry bracketed text of two different kinds:
///
///   "lepinja, pariška salama (pšenica, mlečni izdelek, ki vsebuje laktozo)"
///   "mehiška solata (paradižnik, paprika, fižol, cvetača, koruza..)"
///
/// The first is a legally required allergen declaration, the second is the
/// actual contents of the dish. Treating them the same way is wrong in both
/// directions: reading the allergen list as food gave two chocolate pastries
/// a protein point for the word "jajca", while discarding every bracket threw
/// away five real vegetables from the salad.
///
/// Pure Dart, so `bin/` scripts can use it too.
library;

/// The EU's fourteen declarable allergens as Slovenian menus spell them,
/// plus the variants this school actually emits.
///
/// Terms are matched whole, never as substrings: "zelena" alone is celery
/// (an allergen), but "zelena solata" is a green salad and must survive.
const _allergenTerms = <String>{
  // Cereals containing gluten
  'gluten', 'pšenica', 'pšenični', 'rž', 'ržena', 'ječmen', 'oves',
  'ovsena', 'pira', 'kamut', 'žita', 'žita z glutenom',
  // Milk
  'mleko', 'mlečni izdelek', 'mlečni izdelki', 'laktoza',
  'ki vsebuje laktozo', 'vsebuje laktozo',
  // Eggs
  'jajca', 'jajce',
  // Fish, crustaceans, molluscs
  'ribe', 'riba', 'raki', 'mehkužci',
  // Peanuts and tree nuts
  'arašidi', 'oreški', 'oreščki', 'orehi', 'lešniki', 'mandlji',
  'mandeljni', 'pistacije', 'indijski oreščki',
  // Soy
  'soja', 'sojin',
  // Celery, mustard, sesame
  'zelena', 'listna zelena', 'gorčica', 'gorčična semena',
  'gorčično seme', 'sezam', 'sezamova semena', 'sezamovo seme',
  // Sulphites, lupin
  'žveplov dioksid', 'sulfiti', 'volčji bob',
};

final _bracketRe = RegExp(r'\(([^)]*)\)');

/// Remove allergen declarations from [description], keeping any bracket that
/// lists real ingredients.
///
/// Works term by term, so a bracket mixing the two — "(pšenica, sir)" —
/// keeps the food and drops the allergen. A bracket left empty is removed
/// along with its parentheses.
String stripAllergenDeclarations(String description) {
  return description
      .replaceAllMapped(_bracketRe, (m) {
        final kept = <String>[
          for (final term in m.group(1)!.split(','))
            if (!_isAllergenTerm(term)) term.trim(),
        ]..removeWhere((t) => t.isEmpty);
        return kept.isEmpty ? '' : '(${kept.join(', ')})';
      })
      // Collapse the whitespace and dangling commas a removal leaves behind.
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s+,'), ',')
      .trim();
}

bool _isAllergenTerm(String raw) {
  // "koruza..", "pšenica ." — trailing punctuation is common.
  final term = raw.trim().toLowerCase().replaceAll(RegExp(r'[.\s]+$'), '');
  if (term.isEmpty) return true;
  if (_allergenTerms.contains(term)) return true;
  // "sledi oreščkov", "sledi soje" — a traces-of declaration.
  if (term.startsWith('sledi ')) return true;
  // "ječmen-gluten", "pira-gluten" — this school hyphenates the grain to
  // the allergen it carries.
  if (term.contains('-')) {
    return term.split('-').every((part) => _isAllergenTerm(part));
  }
  return false;
}

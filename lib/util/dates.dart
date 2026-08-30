/// Slovenian date formatting, defined once.
///
/// The day-name map and the `YYYY-MM-DD` formatter used to be copied into
/// three screens and two services. They had already drifted — the scheduler's
/// copy was fine, but nothing stopped the next edit from fixing a label on one
/// screen and leaving the other two showing the old one.
library;

const kDayNames = <int, String>{
  1: 'Ponedeljek',
  2: 'Torek',
  3: 'Sreda',
  4: 'Četrtek',
  5: 'Petek',
  6: 'Sobota',
  7: 'Nedelja',
};

const kDayNamesShort = <int, String>{
  1: 'Pon',
  2: 'Tor',
  3: 'Sre',
  4: 'Čet',
  5: 'Pet',
  6: 'Sob',
  7: 'Ned',
};

/// `YYYY-MM-DD` — the wire format eAsistent uses for every date.
String fmtYmd(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// "Ponedeljek, 1. 9." — the day-section heading on the menu screen.
String formatDayDate(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return '${kDayNames[d.weekday] ?? ''}, ${d.day}. ${d.month}.';
}

/// "Pon 1.9." — the compact form used in confirmation lists.
String formatDayShort(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return '${kDayNamesShort[d.weekday] ?? ''} ${d.day}.${d.month}.';
}

/// "Ponedeljek, 1. 9. 2025" — the log screen's fuller form.
String formatDayDateYear(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return '${kDayNames[d.weekday] ?? ''}, ${d.day}. ${d.month}. ${d.year}';
}

/// Monday of the week containing [d].
DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

String _two(int n) => n.toString().padLeft(2, '0');

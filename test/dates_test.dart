import 'package:easistent_meal_picker/util/dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fmtYmd', () {
    test('zero-pads month and day to the wire format', () {
      expect(fmtYmd(DateTime(2025, 9, 1)), '2025-09-01');
      expect(fmtYmd(DateTime(2025, 12, 31)), '2025-12-31');
    });
  });

  group('formatters', () {
    test('formatDayDate renders the Slovenian weekday', () {
      // 1 September 2025 is a Monday.
      expect(formatDayDate('2025-09-01'), 'Ponedeljek, 1. 9.');
      expect(formatDayDate('2025-09-04'), 'Četrtek, 4. 9.');
    });

    test('formatDayShort abbreviates to three characters', () {
      expect(formatDayShort('2025-09-01'), 'Pon 1.9.');
      expect(formatDayShort('2025-09-04'), 'Čet 4.9.');
    });

    test('formatDayDateYear includes the year', () {
      expect(formatDayDateYear('2025-09-01'), 'Ponedeljek, 1. 9. 2025');
    });

    test('unparseable input is echoed back rather than throwing', () {
      // The log screen feeds these straight from stored JSON, which a
      // hand-edit or an older format version can leave malformed. The old
      // per-screen copies used bare DateTime.parse and threw here.
      expect(formatDayDate('not-a-date'), 'not-a-date');
      expect(formatDayShort(''), '');
      expect(formatDayDateYear('garbage'), 'garbage');
    });

    test('out-of-range components roll over, as DateTime.parse always did', () {
      // Documenting rather than endorsing: month 13 becomes January of the
      // next year. eAsistent never emits these, and rejecting them would be
      // a behaviour change from the code this replaced.
      expect(formatDayDateYear('2025-13-45'), 'Sobota, 14. 2. 2026');
    });
  });

  group('mondayOf', () {
    test('returns the same day for a Monday', () {
      expect(mondayOf(DateTime(2025, 9, 1)), DateTime(2025, 9, 1));
    });

    test('walks back from any weekday', () {
      expect(mondayOf(DateTime(2025, 9, 4)), DateTime(2025, 9, 1));
      expect(mondayOf(DateTime(2025, 9, 7)), DateTime(2025, 9, 1));
    });

    test('strips the time component', () {
      expect(mondayOf(DateTime(2025, 9, 3, 18, 42)), DateTime(2025, 9, 1));
    });
  });
}

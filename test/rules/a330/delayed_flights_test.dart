import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/rules/a330/max_duty/delayed_flights.dart';

void main() {
  group('A330 — Delayed Flights modifier (3.7/3.8)', () {
    test('Continental: delay under 2h uses the actual report time', () {
      final rostered = DateTime(2026, 9, 29, 8, 0);
      final actual = DateTime(2026, 9, 29, 9, 59); // 1h59 delay
      final result = effectiveReportTimeForDelay(
        rosteredReport: rostered,
        actualReport: actual,
        isIntercontinental: false,
      );
      expect(result, actual);
    });

    test('Continental: delay of exactly 2h uses rostered + 2h', () {
      final rostered = DateTime(2026, 9, 29, 8, 0);
      final actual = DateTime(2026, 9, 29, 10, 0); // 2h delay
      final result = effectiveReportTimeForDelay(
        rosteredReport: rostered,
        actualReport: actual,
        isIntercontinental: false,
      );
      expect(result, rostered.add(const Duration(hours: 2)));
    });

    test('Continental: delay well over 2h still caps at rostered + 2h', () {
      final rostered = DateTime(2026, 9, 29, 8, 0);
      final actual = DateTime(2026, 9, 29, 14, 0); // 6h delay
      final result = effectiveReportTimeForDelay(
        rosteredReport: rostered,
        actualReport: actual,
        isIntercontinental: false,
      );
      expect(result, rostered.add(const Duration(hours: 2)));
    });

    test('Intercontinental: delay under 4h uses the actual report time', () {
      final rostered = DateTime(2026, 9, 29, 8, 0);
      final actual = DateTime(2026, 9, 29, 11, 59); // 3h59 delay
      final result = effectiveReportTimeForDelay(
        rosteredReport: rostered,
        actualReport: actual,
        isIntercontinental: true,
      );
      expect(result, actual);
    });

    test('Intercontinental: delay of exactly 4h uses rostered + 4h', () {
      final rostered = DateTime(2026, 9, 29, 8, 0);
      final actual = DateTime(2026, 9, 29, 12, 0); // 4h delay
      final result = effectiveReportTimeForDelay(
        rosteredReport: rostered,
        actualReport: actual,
        isIntercontinental: true,
      );
      expect(result, rostered.add(const Duration(hours: 4)));
    });
  });
}

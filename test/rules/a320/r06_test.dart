import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/change_of_duty/r06.dart';

void main() {
  group('R-06 — Change of duty, Intercontinental, ≥14h notice, at Base '
      '(3.2.4c)', () {
    final originalReport = DateTime(2026, 9, 29, 10, 0);

    test('within ±2h with 14h notice complies (green)', () {
      final result = verifyR06(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 8, 0),
        noticeGiven: const Duration(hours: 14),
      );
      expect(result.color, RuleColor.green);
    });

    test('more than 2h later with 14h notice does NOT comply (amber)', () {
      final result = verifyR06(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 1),
        noticeGiven: const Duration(hours: 14),
      );
      expect(result.color, RuleColor.amber);
    });

    test('more than 2h earlier WITHOUT pilot consent does NOT comply '
        '(amber)', () {
      final result = verifyR06(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 7, 59),
        noticeGiven: const Duration(hours: 14),
      );
      expect(result.color, RuleColor.amber);
    });

    test('more than 2h earlier WITH pilot consent complies (green)', () {
      final result = verifyR06(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 6, 0),
        noticeGiven: const Duration(hours: 14),
        pilotConsents: true,
      );
      expect(result.color, RuleColor.green);
    });

    test('insufficient notice (< 14h) does NOT comply (amber)', () {
      final result = verifyR06(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 11, 0),
        noticeGiven: const Duration(hours: 13, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/change_of_duty/r02.dart';

void main() {
  group('R-02 — Change of duty, Continental, ≥24h notice, at Base '
      '(3.2.3b)', () {
    final originalReport = DateTime(2026, 9, 29, 10, 0);

    test('within ±2h with 24h notice complies (green)', () {
      final result = verifyR02(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 0),
        noticeGiven: const Duration(hours: 24),
      );
      expect(result.color, RuleColor.green);
    });

    test('more than 2h later with 24h notice does NOT comply (amber)', () {
      final result = verifyR02(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 12, 1),
        noticeGiven: const Duration(hours: 24),
      );
      expect(result.color, RuleColor.amber);
    });

    test('more than 2h earlier with 24h notice does NOT comply (amber)', () {
      final result = verifyR02(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 7, 59),
        noticeGiven: const Duration(hours: 24),
      );
      expect(result.color, RuleColor.amber);
    });

    test('insufficient notice (< 24h) does NOT comply (amber)', () {
      final result = verifyR02(
        originalReport: originalReport,
        newReport: DateTime(2026, 9, 29, 11, 0),
        noticeGiven: const Duration(hours: 23, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
    });
  });
}

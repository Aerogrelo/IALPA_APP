import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/change_of_duty/r04.dart';

void main() {
  group('R-04 — Standby before 0800 brought forward (3.2.3f)', () {
    final originalStandbyStart = DateTime(2026, 9, 29, 7, 0);

    test('not brought forward (same or later) complies (green)', () {
      final result = verifyR04(
        originalStandbyStart: originalStandbyStart,
        newStandbyStart: DateTime(2026, 9, 29, 7, 30),
        noticeGiven: Duration.zero,
      );
      expect(result.color, RuleColor.green);
    });

    test('original does not start before 0800 — clause does not apply '
        '(green)', () {
      final result = verifyR04(
        originalStandbyStart: DateTime(2026, 9, 29, 8, 0),
        newStandbyStart: DateTime(2026, 9, 29, 6, 0),
        noticeGiven: Duration.zero,
      );
      expect(result.color, RuleColor.green);
    });

    test('brought forward 1h with 12h notice complies (green)', () {
      final result = verifyR04(
        originalStandbyStart: originalStandbyStart,
        newStandbyStart: DateTime(2026, 9, 29, 6, 0),
        noticeGiven: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.green);
    });

    test('brought forward 2h with 24h notice complies (green)', () {
      final result = verifyR04(
        originalStandbyStart: originalStandbyStart,
        newStandbyStart: DateTime(2026, 9, 29, 5, 0),
        noticeGiven: const Duration(hours: 24),
      );
      expect(result.color, RuleColor.green);
    });

    test('brought forward 1h with only 11h notice does NOT comply '
        '(amber)', () {
      final result = verifyR04(
        originalStandbyStart: originalStandbyStart,
        newStandbyStart: DateTime(2026, 9, 29, 6, 0),
        noticeGiven: const Duration(hours: 11),
      );
      expect(result.color, RuleColor.amber);
    });

    test('brought forward 2h with only 12h notice does NOT comply '
        '(amber)', () {
      final result = verifyR04(
        originalStandbyStart: originalStandbyStart,
        newStandbyStart: DateTime(2026, 9, 29, 5, 0),
        noticeGiven: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.amber);
    });
  });
}

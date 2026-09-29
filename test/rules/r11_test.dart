import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/rest/r11.dart';

void main() {
  group(
      'R-11 — Minimum rest after a same-day-return Intercontinental duty '
      '(3.14.3b)', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 12, 0), // 6h -> formula gives 8h, floor wins
      type: DutyType.flight,
    );

    test('11h59 rest does NOT comply (red) when the 12h floor governs', () {
      final result = verifyR11(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('12h00 rest DOES comply (green) when the 12h floor governs', () {
      final result = verifyR11(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.green);
    });

    final longDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 17, 0), // 11h -> formula gives 13h
      type: DutyType.flight,
    );

    test(
        'with a long duty, the formula (duty+2h) governs, not the 12h '
        'floor — but 12h59 still clears the 12h EASA floor, so it is '
        'amber (OWC), not red', () {
      final insufficient = verifyR11(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 12, minutes: 59),
      );
      expect(insufficient.color, RuleColor.amber);

      final sufficient = verifyR11(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 13),
      );
      expect(sufficient.color, RuleColor.green);
    });
  });

  group('R-11 — EASA floor (amber vs red, 2026-09-28)', () {
    final duty11h = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 17, 0),
      type: DutyType.flight,
    );

    test('12h00 rest breaches the 13h convenio minimum but meets the 12h '
        'EASA floor -> amber (OWC)', () {
      final result = verifyR11(
        previousDuty: duty11h,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('OWC'));
    });

    test('11h59 rest breaches both the convenio and the EASA floor -> red',
        () {
      final result = verifyR11(
        previousDuty: duty11h,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });
  });
}

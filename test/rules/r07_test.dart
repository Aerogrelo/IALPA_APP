import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/rest/r07.dart';

void main() {
  group('R-07 — Minimum rest at an Outstation after Continental duty (3.14.1b)',
      () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 12, 0), // 6h -> formula gives 8h, floor wins
      type: DutyType.flight,
    );

    test(
        '10h59 rest does NOT comply with the 11h convenio floor, but meets '
        'the 10h EASA floor -> amber (OWC), not red', () {
      final result = verifyR07(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 10, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
    });

    test('9h59 rest breaches both the convenio and the EASA floor -> red',
        () {
      final result = verifyR07(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 9, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('11h00 rest DOES comply (green) when the 11h floor governs', () {
      final result = verifyR07(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 11),
      );
      expect(result.color, RuleColor.green);
    });

    final longDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 17, 0), // 11h -> formula gives 13h
      type: DutyType.flight,
    );

    test(
        'with a long duty, the formula (duty+2h) governs, not the 11h '
        'floor — but 12h59 still clears the 11h EASA floor, so it is '
        'amber (OWC), not red', () {
      final insufficient = verifyR07(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 12, minutes: 59),
      );
      expect(insufficient.color, RuleColor.amber);

      final sufficient = verifyR07(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 13),
      );
      expect(sufficient.color, RuleColor.green);
    });
  });

  group('R-07 — EASA floor (amber vs red, 2026-09-28)', () {
    // Previous duty of 11h -> EASA floor (away from base) = max(11h,10h)=11h.
    final duty11h = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 17, 0),
      type: DutyType.flight,
    );

    test('11h00 rest breaches the 13h convenio minimum but meets the 11h '
        'EASA floor -> amber (OWC)', () {
      final result = verifyR07(
        previousDuty: duty11h,
        plannedRest: const Duration(hours: 11),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('OWC'));
    });

    test('10h59 rest breaches both the convenio and the EASA floor -> red',
        () {
      final result = verifyR07(
        previousDuty: duty11h,
        plannedRest: const Duration(hours: 10, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });
  });
}

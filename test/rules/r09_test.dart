import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/rest/r09.dart';

void main() {
  group('R-09 — Minimum rest after a westbound transatlantic duty (3.14.2b)',
      () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 12, 0),
      end: DateTime(2026, 9, 28, 20, 0), // 8h + 5h TD = 13h, floor 18h wins
      type: DutyType.flight,
      transatlanticDirection: TransatlanticDirection.westbound,
      timeDifference: const Duration(hours: 5),
    );

    test(
        '17h59 rest does NOT meet the convenio floor (18h), but clears the '
        'EASA at-base floor (12h) -> amber (OWC), not red', () {
      final result = verifyR09(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 17, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('OWC'));
    });

    test('18h00 rest DOES comply (green) when the 18h floor governs', () {
      final result = verifyR09(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 18),
      );
      expect(result.color, RuleColor.green);
    });

    final longDuty = Duty(
      report: DateTime(2026, 9, 28, 12, 0),
      end: DateTime(2026, 9, 29, 1, 0), // 13h + 8h TD = 21h, formula governs
      type: DutyType.flight,
      transatlanticDirection: TransatlanticDirection.westbound,
      timeDifference: const Duration(hours: 8),
    );

    test(
        'with a long duty and large time difference, the formula governs, '
        'not the 18h floor — but 20h59 still clears the 13h EASA floor '
        '(no time-difference term), so it is amber (OWC), not red', () {
      final insufficient = verifyR09(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 20, minutes: 59),
      );
      expect(insufficient.color, RuleColor.amber);

      final sufficient = verifyR09(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 21),
      );
      expect(sufficient.color, RuleColor.green);
    });
  });

  group('R-09 — EASA floor (amber vs red, 2026-09-28)', () {
    final duty13h = Duty(
      report: DateTime(2026, 9, 28, 12, 0),
      end: DateTime(2026, 9, 29, 1, 0), // 13h
      type: DutyType.flight,
      transatlanticDirection: TransatlanticDirection.westbound,
      timeDifference: const Duration(hours: 8),
    );

    test('13h00 rest breaches the 21h convenio minimum but meets the 13h '
        'EASA floor (preceding duty, no time-difference term) -> amber '
        '(OWC)', () {
      final result = verifyR09(
        previousDuty: duty13h,
        plannedRest: const Duration(hours: 13),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('OWC'));
    });

    test('12h59 rest breaches both the convenio and the EASA floor -> red',
        () {
      final result = verifyR09(
        previousDuty: duty13h,
        plannedRest: const Duration(hours: 12, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/rest/r08.dart';

void main() {
  group('R-08 — Minimum rest after a through-the-night duty (3.14.1c)', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 1, 0),
      end: DateTime(2026, 9, 28, 5, 0), // 4h -> formula gives 8h, floor wins
      type: DutyType.flight,
    );

    test(
        '13h59 rest does NOT meet the convenio floor (14h), but clears the '
        'EASA floor (12h) -> amber (OWC), not red', () {
      final result = verifyR08(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 13, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('OWC'));
    });

    test('14h00 rest DOES comply (green) when the 14h floor governs', () {
      final result = verifyR08(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 14),
      );
      expect(result.color, RuleColor.green);
    });

    final longDuty = Duty(
      report: DateTime(2026, 9, 28, 1, 0),
      end: DateTime(2026, 9, 28, 13, 0), // 12h -> formula gives 16h
      type: DutyType.flight,
    );

    test(
        'with a long duty, the formula (duty+4h) governs, not the 14h '
        'floor — but 15h59 still clears the 12h EASA floor, so it is '
        'amber (OWC), not red', () {
      final insufficient = verifyR08(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 15, minutes: 59),
      );
      expect(insufficient.color, RuleColor.amber);

      final sufficient = verifyR08(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 16),
      );
      expect(sufficient.color, RuleColor.green);
    });

    test('isThroughTheNight is true for a duty encompassing 0330', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 1, 0),
        end: DateTime(2026, 9, 28, 5, 0),
        type: DutyType.flight,
      );
      expect(duty.isThroughTheNight, isTrue);
    });
  });

  group('R-08 — EASA floor (amber vs red, 2026-09-28)', () {
    final duty12h = Duty(
      report: DateTime(2026, 9, 28, 1, 0),
      end: DateTime(2026, 9, 28, 13, 0), // 12h
      type: DutyType.flight,
    );

    test('12h00 rest breaches the 16h convenio minimum but meets the 12h '
        'EASA floor -> amber (OWC)', () {
      final result = verifyR08(
        previousDuty: duty12h,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('OWC'));
    });

    test('11h59 rest breaches both the convenio and the EASA floor -> red',
        () {
      final result = verifyR08(
        previousDuty: duty12h,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });
  });
}

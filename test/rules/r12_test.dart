import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/rest/r12.dart';

void main() {
  group('R-12 — Minimum rest after Standby (3.17.5)', () {
    test('no duty assigned: 11h59 does NOT comply (red)', () {
      final result = verifyR12(
        dutyAssignedOnStandby: null,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('no duty assigned: 12h00 DOES comply (green)', () {
      final result = verifyR12(
        dutyAssignedOnStandby: null,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.green);
    });

    // With a short assigned duty (6h) -> formula gives 8h, 12h floor wins.
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 12, 0),
      type: DutyType.flight,
    );

    test('with a short assigned duty: 11h59 does NOT comply (red)', () {
      final result = verifyR12(
        dutyAssignedOnStandby: shortDuty,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('with a short assigned duty: 12h00 DOES comply (green)', () {
      final result = verifyR12(
        dutyAssignedOnStandby: shortDuty,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.green);
    });

    // With a long assigned duty (11h) -> formula gives 13h, formula governs.
    final longDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 17, 0),
      type: DutyType.flight,
    );

    test(
        'with a long assigned duty, the formula (duty+2h) governs, not the '
        '12h floor — but 12h59 still clears the 12h EASA floor, so it is '
        'amber (OWC), not red', () {
      final insufficient = verifyR12(
        dutyAssignedOnStandby: longDuty,
        plannedRest: const Duration(hours: 12, minutes: 59),
      );
      expect(insufficient.color, RuleColor.amber);

      final sufficient = verifyR12(
        dutyAssignedOnStandby: longDuty,
        plannedRest: const Duration(hours: 13),
      );
      expect(sufficient.color, RuleColor.green);
    });
  });

  group('R-12 — EASA floor (amber vs red, 2026-09-28)', () {
    final duty11h = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 17, 0),
      type: DutyType.flight,
    );

    test('12h00 rest breaches the 13h convenio minimum but meets the 12h '
        'EASA floor -> amber (OWC)', () {
      final result = verifyR12(
        dutyAssignedOnStandby: duty11h,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('OWC'));
    });

    test('11h59 rest breaches both the convenio and the EASA floor -> red',
        () {
      final result = verifyR12(
        dutyAssignedOnStandby: duty11h,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('no duty assigned: EASA floor equals the convenio floor (12h), so '
        'there is no amber zone — 11h59 stays red', () {
      final result = verifyR12(
        dutyAssignedOnStandby: null,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });
  });
}

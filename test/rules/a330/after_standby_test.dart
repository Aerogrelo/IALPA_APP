import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/rest/after_standby.dart';

void main() {
  group('A330 — Minimum rest after completing a Standby duty (3.16.10)', () {
    test('12h59 rest does NOT comply (red), no EASA data given', () {
      final result = verifyA330AfterStandbyRest(
        plannedRest: const Duration(hours: 12, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('13h00 rest DOES comply (green)', () {
      final result = verifyA330AfterStandbyRest(
        plannedRest: const Duration(hours: 13),
      );
      expect(result.color, RuleColor.green);
    });
  });

  group('A330 — EASA floor (amber vs red) after standby', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 12, 0), // 6h duty -> EASA floor 12h governs
      type: DutyType.flight,
    );

    test('11h59 rest falls short of EASA floor too (red)', () {
      final result = verifyA330AfterStandbyRest(
        plannedRest: const Duration(hours: 11, minutes: 59),
        dutyAssignedOnStandby: shortDuty,
      );
      expect(result.color, RuleColor.red);
    });

    test('12h00 rest breaches the convenio (13h) but meets EASA (amber)',
        () {
      final result = verifyA330AfterStandbyRest(
        plannedRest: const Duration(hours: 12),
        dutyAssignedOnStandby: shortDuty,
      );
      expect(result.color, RuleColor.amber);
    });

    test('13h00 rest DOES comply with the convenio (green)', () {
      final result = verifyA330AfterStandbyRest(
        plannedRest: const Duration(hours: 13),
        dutyAssignedOnStandby: shortDuty,
      );
      expect(result.color, RuleColor.green);
    });
  });
}

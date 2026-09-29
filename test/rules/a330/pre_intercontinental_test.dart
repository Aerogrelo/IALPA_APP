import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/rest/pre_intercontinental.dart';

void main() {
  group('A330 — Minimum rest before an intercontinental duty (3.13)', () {
    test('14h59 rest does NOT comply (red) when not preceded by standby '
        '(15h floor)', () {
      final result = verifyA330PreIntercontinentalRest(
        plannedRest: const Duration(hours: 14, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('15h00 rest DOES comply (green) when not preceded by standby', () {
      final result = verifyA330PreIntercontinentalRest(
        plannedRest: const Duration(hours: 15),
      );
      expect(result.color, RuleColor.green);
    });

    test('12h59 rest does NOT comply (red) when preceded by standby '
        '(13h floor)', () {
      final result = verifyA330PreIntercontinentalRest(
        plannedRest: const Duration(hours: 12, minutes: 59),
        precededByStandby: true,
      );
      expect(result.color, RuleColor.red);
    });

    test('13h00 rest DOES comply (green) when preceded by standby', () {
      final result = verifyA330PreIntercontinentalRest(
        plannedRest: const Duration(hours: 13),
        precededByStandby: true,
      );
      expect(result.color, RuleColor.green);
    });
  });

  group('A330 — EASA floor (amber vs red) for pre-intercontinental rest', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 12, 0), // 6h duty -> EASA floor 12h governs
      type: DutyType.flight,
    );

    test('11h59 rest does NOT comply and falls short of EASA floor (red)',
        () {
      final result = verifyA330PreIntercontinentalRest(
        plannedRest: const Duration(hours: 11, minutes: 59),
        previousDuty: shortDuty,
      );
      expect(result.color, RuleColor.red);
    });

    test('12h00 rest breaches the convenio (15h) but meets EASA (amber)',
        () {
      final result = verifyA330PreIntercontinentalRest(
        plannedRest: const Duration(hours: 12),
        previousDuty: shortDuty,
      );
      expect(result.color, RuleColor.amber);
    });

    test('14h59 rest still amber (just below the 15h convenio floor)', () {
      final result = verifyA330PreIntercontinentalRest(
        plannedRest: const Duration(hours: 14, minutes: 59),
        previousDuty: shortDuty,
      );
      expect(result.color, RuleColor.amber);
    });

    test('15h00 rest DOES comply with the convenio (green)', () {
      final result = verifyA330PreIntercontinentalRest(
        plannedRest: const Duration(hours: 15),
        previousDuty: shortDuty,
      );
      expect(result.color, RuleColor.green);
    });
  });
}

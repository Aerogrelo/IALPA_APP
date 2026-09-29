import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/rest/base_continental.dart';

void main() {
  group('A330 — Minimum rest at base after a Continental duty (3.13)', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 12, 0), // 6h -> formula gives 8h, floor wins
      type: DutyType.flight,
    );

    test('11h59 rest does NOT comply (red) when the 12h floor governs', () {
      final result = verifyA330BaseContinentalRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('12h00 rest DOES comply (green) when the 12h floor governs', () {
      final result = verifyA330BaseContinentalRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.green);
    });
  });

  group('A330 — EASA floor (amber vs red) at base after a Continental '
      'duty', () {
    final longDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 17, 0), // 11h -> formula gives 13h
      type: DutyType.flight,
    );

    test('11h59 rest does NOT comply and falls short of EASA floor (red)',
        () {
      final result = verifyA330BaseContinentalRest(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('12h00 rest breaches the convenio (13h) but meets EASA (amber)',
        () {
      final result = verifyA330BaseContinentalRest(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.amber);
    });

    test('12h59 rest still amber (just below the 13h convenio floor)', () {
      final result = verifyA330BaseContinentalRest(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 12, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
    });

    test('13h00 rest DOES comply with the convenio (green)', () {
      final result = verifyA330BaseContinentalRest(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 13),
      );
      expect(result.color, RuleColor.green);
    });
  });
}

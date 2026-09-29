import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/rest/through_the_night.dart';

void main() {
  group('A330 — Minimum rest after a through-the-night duty (3.13)', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 1, 0),
      end: DateTime(2026, 9, 28, 5, 0), // 4h -> formula gives 8h, floor wins
      type: DutyType.flight,
    );

    test('13h59 rest breaches the convenio 14h floor but meets the EASA '
        'floor (amber)', () {
      final result = verifyA330ThroughTheNightRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 13, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
    });

    test('14h00 rest DOES comply (green) when the 14h floor governs', () {
      final result = verifyA330ThroughTheNightRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 14),
      );
      expect(result.color, RuleColor.green);
    });
  });

  group('A330 — EASA floor (amber vs red) after a through-the-night '
      'duty', () {
    final longDuty = Duty(
      report: DateTime(2026, 9, 28, 1, 0),
      end: DateTime(2026, 9, 28, 12, 0), // 11h -> formula gives 15h
      type: DutyType.flight,
    );

    test('11h59 rest does NOT comply and falls short of EASA floor (red)',
        () {
      final result = verifyA330ThroughTheNightRest(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('12h00 rest breaches the convenio (15h) but meets EASA (amber)',
        () {
      final result = verifyA330ThroughTheNightRest(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.amber);
    });

    test('14h59 rest still amber (just below the 15h convenio floor)', () {
      final result = verifyA330ThroughTheNightRest(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 14, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
    });

    test('15h00 rest DOES comply with the convenio (green)', () {
      final result = verifyA330ThroughTheNightRest(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 15),
      );
      expect(result.color, RuleColor.green);
    });
  });
}

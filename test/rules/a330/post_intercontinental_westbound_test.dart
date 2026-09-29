import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/rest/post_intercontinental_westbound.dart';

void main() {
  group('A330 — Minimum rest after a westbound intercontinental duty '
      '(3.13.2)', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 12, 0),
      end: DateTime(2026, 9, 28, 20, 0), // 8h + 5h TD = 13h, floor 18h wins
      type: DutyType.flight,
      transatlanticDirection: TransatlanticDirection.westbound,
      timeDifference: const Duration(hours: 5),
    );

    test('17h59 rest breaches the convenio 18h floor but meets the EASA '
        'floor (amber)', () {
      final result = verifyA330PostIntercontinentalWestboundRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 17, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
    });

    test('18h00 rest DOES comply (green) when the 18h floor governs', () {
      final result = verifyA330PostIntercontinentalWestboundRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 18),
      );
      expect(result.color, RuleColor.green);
    });
  });

  group('A330 — EASA floor (amber vs red) after a westbound '
      'intercontinental duty', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 12, 0),
      end: DateTime(2026, 9, 28, 20, 0), // 8h duty -> EASA floor 12h governs
      type: DutyType.flight,
      transatlanticDirection: TransatlanticDirection.westbound,
      timeDifference: const Duration(hours: 5),
    );

    test('11h59 rest does NOT comply and falls short of EASA floor (red)',
        () {
      final result = verifyA330PostIntercontinentalWestboundRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('12h00 rest breaches the convenio (18h) but meets EASA (amber)',
        () {
      final result = verifyA330PostIntercontinentalWestboundRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.amber);
    });

    test('17h59 rest still amber (just below the 18h convenio floor)', () {
      final result = verifyA330PostIntercontinentalWestboundRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 17, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
    });
  });
}

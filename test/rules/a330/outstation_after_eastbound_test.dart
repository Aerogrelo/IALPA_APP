import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/rest/outstation_after_eastbound.dart';

void main() {
  group('A330 — Minimum rest at outstation after an eastbound '
      'intercontinental duty (3.13)', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 12, 0),
      end: DateTime(2026, 9, 28, 18, 0), // 6h + 5h TD = 11h, floor 14h wins
      type: DutyType.flight,
      transatlanticDirection: TransatlanticDirection.eastbound,
      timeDifference: const Duration(hours: 5),
    );

    test('13h59 rest does NOT comply (red) when the 14h floor governs', () {
      final result = verifyA330OutstationAfterEastboundRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 13, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('14h00 rest DOES comply (green) when the 14h floor governs', () {
      final result = verifyA330OutstationAfterEastboundRest(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 14),
      );
      expect(result.color, RuleColor.green);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/rest/r10.dart';

void main() {
  group(
      'R-10 — Minimum rest at an Outstation after an eastbound transatlantic '
      'duty (3.14.2e)', () {
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 12, 0),
      end: DateTime(2026, 9, 28, 18, 0), // 6h + 5h TD = 11h, floor 14h wins
      type: DutyType.flight,
      transatlanticDirection: TransatlanticDirection.eastbound,
      timeDifference: const Duration(hours: 5),
    );

    test('13h59 rest does NOT comply (red) when the 14h floor governs', () {
      final result = verifyR10(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 13, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('14h00 rest DOES comply (green) when the 14h floor governs', () {
      final result = verifyR10(
        previousDuty: shortDuty,
        plannedRest: const Duration(hours: 14),
      );
      expect(result.color, RuleColor.green);
    });

    final longDuty = Duty(
      report: DateTime(2026, 9, 28, 12, 0),
      end: DateTime(2026, 9, 28, 22, 0), // 10h + 8h TD = 18h, formula governs
      type: DutyType.flight,
      transatlanticDirection: TransatlanticDirection.eastbound,
      timeDifference: const Duration(hours: 8),
    );

    test(
        'with a long duty and large time difference, the formula governs, '
        'not the 14h floor', () {
      final insufficient = verifyR10(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 17, minutes: 59),
      );
      expect(insufficient.color, RuleColor.red);

      final sufficient = verifyR10(
        previousDuty: longDuty,
        plannedRest: const Duration(hours: 18),
      );
      expect(sufficient.color, RuleColor.green);
    });
  });

  group('R-10 — no EASA amber zone here (checked 2026-09-28)', () {
    // Unlike R-06/R-07/R-08/R-09/R-11/R-12, R-10's convenio floor (duty +
    // time difference, min 14h, away from base) is IDENTICAL to EASA's own
    // floor for the same situation, so there is no gap to open an amber
    // zone in — a breach here stays red because it is also illegal under
    // EASA, not just a breach of the agreement.
    test('a breach of the convenio floor is red, never amber', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 12, 0),
        end: DateTime(2026, 9, 28, 18, 0),
        type: DutyType.flight,
        transatlanticDirection: TransatlanticDirection.eastbound,
        timeDifference: const Duration(hours: 5),
      );
      final result = verifyR10(
        previousDuty: duty,
        plannedRest: const Duration(hours: 13, minutes: 59),
      );
      expect(result.color, RuleColor.red);
      expect(result.explanation, contains('EASA'));
    });
  });
}

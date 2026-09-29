import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/max_duty/r15.dart';

void main() {
  group('R-15 — Maximum Flight Duty Time, Intercontinental (3.11.2)', () {
    test(
        'Intercontinental, non-eastbound, non-deadheading: 14h00 complies, '
        "14h01 is within the EASA Commander's discretion window (amber, "
        'not red)', () {
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 22, 0), // 14h
        type: DutyType.flight,
      );
      expect(verifyR15(duty: compliant).color, RuleColor.green);

      final breach = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 22, 1), // 14h01
        type: DutyType.flight,
      );
      expect(verifyR15(duty: breach).color, RuleColor.amber);
    });

    test(
        'Eastbound Transatlantic, non-deadheading: 12h00 complies, 12h01 '
        "is within the EASA Commander's discretion window (amber, not "
        'red)', () {
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 20, 0), // 12h
        type: DutyType.flight,
        transatlanticDirection: TransatlanticDirection.eastbound,
      );
      expect(verifyR15(duty: compliant).color, RuleColor.green);

      final breach = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 20, 1), // 12h01
        type: DutyType.flight,
        transatlanticDirection: TransatlanticDirection.eastbound,
      );
      expect(verifyR15(duty: breach).color, RuleColor.amber);
    });

    test(
        "deadheading, non-eastbound: 16h00 complies, 16h01 is within the "
        "EASA Commander's discretion window (amber, not red)", () {
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 29, 0, 0), // 16h
        type: DutyType.flight,
        deadheading: true,
      );
      expect(verifyR15(duty: compliant).color, RuleColor.green);

      final breach = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 29, 0, 1), // 16h01
        type: DutyType.flight,
        deadheading: true,
      );
      expect(verifyR15(duty: breach).color, RuleColor.amber);
    });

    test(
        "deadheading, Eastbound Transatlantic: 14h00 complies, 14h01 is "
        "within the EASA Commander's discretion window (amber, not red)",
        () {
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 22, 0), // 14h
        type: DutyType.flight,
        deadheading: true,
        transatlanticDirection: TransatlanticDirection.eastbound,
      );
      expect(verifyR15(duty: compliant).color, RuleColor.green);

      final breach = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 22, 1), // 14h01
        type: DutyType.flight,
        deadheading: true,
        transatlanticDirection: TransatlanticDirection.eastbound,
      );
      expect(verifyR15(duty: breach).color, RuleColor.amber);
    });
  });

  group("R-15 — Commander's discretion EASA window (2026-09-28)", () {
    // Eastbound TA base max = 12h. Discretion window extends it by 2h -> 14h.
    test('14h00 (max +2h) still amber, 14h01 exceeds even the discretion '
        'window -> red', () {
      final atDiscretionLimit = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 22, 0), // 14h
        type: DutyType.flight,
        transatlanticDirection: TransatlanticDirection.eastbound,
      );
      expect(verifyR15(duty: atDiscretionLimit).color, RuleColor.amber);

      final beyondDiscretion = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 22, 1), // 14h01
        type: DutyType.flight,
        transatlanticDirection: TransatlanticDirection.eastbound,
      );
      expect(verifyR15(duty: beyondDiscretion).color, RuleColor.red);
    });
  });

  group('R-15 — preceding standby (STBH 50% / STBA 100%, 29/09)', () {
    // Non-eastbound, non-deadheading base max = 14h. A 10h duty leaves room.
    test('a preceding STBH only counts at 50% towards the max', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 18, 0), // 10h
        type: DutyType.flight,
      );
      // 10h duty + 8h STBH (halved to 4h) = 14h effective, exactly the max.
      final atMax = verifyR15(
        duty: duty,
        stbhPortion: const Duration(hours: 8),
      );
      expect(atMax.color, RuleColor.green);

      // 10h duty + 8h30 STBH (halved to 4h15) = 14h15, past the max ->
      // amber.
      final breach = verifyR15(
        duty: duty,
        stbhPortion: const Duration(hours: 8, minutes: 30),
      );
      expect(breach.color, RuleColor.amber);
    });

    test('a preceding STBA counts in full towards the max', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 18, 0), // 10h
        type: DutyType.flight,
      );
      // 10h duty + 4h STBA (full) = 14h effective, exactly the max.
      final atMax = verifyR15(
        duty: duty,
        stbaPortion: const Duration(hours: 4),
      );
      expect(atMax.color, RuleColor.green);

      // 10h duty + 4h01 STBA (full) = 14h01, past the max -> amber.
      final breach = verifyR15(
        duty: duty,
        stbaPortion: const Duration(hours: 4, minutes: 1),
      );
      expect(breach.color, RuleColor.amber);
    });

    test('the same portion of STBA reduces the margin twice as much as '
        'STBH', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 18, 0), // 10h
        type: DutyType.flight,
      );
      final withStbh =
          verifyR15(duty: duty, stbhPortion: const Duration(hours: 2));
      final withStba =
          verifyR15(duty: duty, stbaPortion: const Duration(hours: 2));
      expect(
        withStba.marginToOwc,
        withStbh.marginToOwc! - const Duration(hours: 1),
      );
    });
  });
}

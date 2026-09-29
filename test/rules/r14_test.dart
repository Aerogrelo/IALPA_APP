import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/max_duty/r14.dart';

void main() {
  group('R-14 — Maximum Flight Duty Time, Continental (3.11.1)', () {
    test(
        'band (a) — report 0100-0549: 11h30 complies, 11h31 is within the '
        "EASA Commander's discretion window (amber, not red)", () {
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 2, 0),
        end: DateTime(2026, 9, 28, 13, 30), // 11h30
        type: DutyType.flight,
      );
      expect(verifyR14(duty: compliant).color, RuleColor.green);

      final breach = Duty(
        report: DateTime(2026, 9, 28, 2, 0),
        end: DateTime(2026, 9, 28, 13, 31), // 11h31
        type: DutyType.flight,
      );
      expect(verifyR14(duty: breach).color, RuleColor.amber);
    });

    test(
        'band (b) — report 0550-0619: 12h00 complies, 12h01 is within the '
        "EASA Commander's discretion window (amber, not red)", () {
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 6, 0),
        end: DateTime(2026, 9, 28, 18, 0), // 12h
        type: DutyType.flight,
      );
      expect(verifyR14(duty: compliant).color, RuleColor.green);

      final breach = Duty(
        report: DateTime(2026, 9, 28, 6, 0),
        end: DateTime(2026, 9, 28, 18, 1), // 12h01
        type: DutyType.flight,
      );
      expect(verifyR14(duty: breach).color, RuleColor.amber);
    });

    test(
        'band (c), no sector reduction — entirely within 0620-0159: 13h00 '
        "complies, 13h01 is within the EASA Commander's discretion window "
        '(amber, not red)', () {
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 21, 0), // 13h, 2 sectors (default)
        type: DutyType.flight,
      );
      expect(verifyR14(duty: compliant).color, RuleColor.green);

      final breach = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 21, 1), // 13h01
        type: DutyType.flight,
      );
      expect(verifyR14(duty: breach).color, RuleColor.amber);
    });

    test(
        'band (c) with sector reduction — 4 sectors reduces the max by 1h '
        "(12h00 complies, 12h01 is within the discretion window, amber)",
        () {
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 20, 0), // 12h
        type: DutyType.flight,
        sectors: 4,
      );
      expect(verifyR14(duty: compliant).color, RuleColor.green);

      final breach = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 20, 1), // 12h01
        type: DutyType.flight,
        sectors: 4,
      );
      expect(verifyR14(duty: breach).color, RuleColor.amber);
    });

    test(
        'band (c) with sector reduction capped at 2h — 10 sectors still '
        'only reduces the max by 2h (11h00 complies, 11h01 is within the '
        'discretion window, amber)', () {
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 19, 0), // 11h
        type: DutyType.flight,
        sectors: 10,
      );
      expect(verifyR14(duty: compliant).color, RuleColor.green);

      final breach = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 19, 1), // 11h01
        type: DutyType.flight,
        sectors: 10,
      );
      expect(verifyR14(duty: breach).color, RuleColor.amber);
    });
  });

  group("R-14 — Commander's discretion EASA window (2026-09-28)", () {
    // Band (c) base max = 13h. Discretion window extends it by 2h -> 15h.
    test('15h00 (max +2h) still amber, 15h01 exceeds even the discretion '
        'window -> red', () {
      final atDiscretionLimit = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 23, 0), // 15h
        type: DutyType.flight,
      );
      expect(verifyR14(duty: atDiscretionLimit).color, RuleColor.amber);

      final beyondDiscretion = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 23, 1), // 15h01
        type: DutyType.flight,
      );
      expect(verifyR14(duty: beyondDiscretion).color, RuleColor.red);
    });
  });

  group('R-14 — preceding standby (STBH 50% / STBA 100%, 29/09)', () {
    // Band (c) base max = 13h. A 9h duty is well within it on its own.
    test('a preceding STBH only counts at 50% towards the max', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 17, 0), // 9h
        type: DutyType.flight,
      );
      // 9h duty + 4h STBH (halved to 2h) = 11h effective, still green.
      final green = verifyR14(
        duty: duty,
        stbhPortion: const Duration(hours: 4),
      );
      expect(green.color, RuleColor.green);

      // 9h duty + 8h STBH (halved to 4h) = 13h effective, exactly the max.
      final atMax = verifyR14(
        duty: duty,
        stbhPortion: const Duration(hours: 8),
      );
      expect(atMax.color, RuleColor.green);

      // 9h duty + 8h30 STBH (halved to 4h15) = 13h15, past the max -> amber.
      final breach = verifyR14(
        duty: duty,
        stbhPortion: const Duration(hours: 8, minutes: 30),
      );
      expect(breach.color, RuleColor.amber);
    });

    test('a preceding STBA counts in full towards the max', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 17, 0), // 9h
        type: DutyType.flight,
      );
      // 9h duty + 4h STBA (full) = 13h effective, exactly the max.
      final atMax = verifyR14(
        duty: duty,
        stbaPortion: const Duration(hours: 4),
      );
      expect(atMax.color, RuleColor.green);

      // 9h duty + 4h01 STBA (full) = 13h01, past the max -> amber.
      final breach = verifyR14(
        duty: duty,
        stbaPortion: const Duration(hours: 4, minutes: 1),
      );
      expect(breach.color, RuleColor.amber);
    });

    test('the same portion of STBA reduces the margin twice as much as '
        'STBH', () {
      final duty = Duty(
        report: DateTime(2026, 9, 28, 8, 0),
        end: DateTime(2026, 9, 28, 17, 0), // 9h
        type: DutyType.flight,
      );
      final withStbh =
          verifyR14(duty: duty, stbhPortion: const Duration(hours: 2));
      final withStba =
          verifyR14(duty: duty, stbaPortion: const Duration(hours: 2));
      expect(
        withStba.marginToOwc,
        withStbh.marginToOwc! - const Duration(hours: 1),
      );
    });
  });
}

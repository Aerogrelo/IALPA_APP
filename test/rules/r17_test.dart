import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/max_duty/r17.dart';

void main() {
  group('R-17 — STBH maximum total elapsed time from standby start '
      '(3.17.2e/f)', () {
    test(
        'Continental, duty entirely within 0630-0059: 16h00 complies, '
        '16h01 does not', () {
      final standbyStart = DateTime(2026, 9, 28, 6, 0);
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 10, 0),
        end: DateTime(2026, 9, 28, 22, 0), // 16h from standby start
        type: DutyType.flight,
      );
      expect(
        verifyR17(
          duty: compliant,
          standbyStart: standbyStart,
          isIntercontinental: false,
        ).color,
        RuleColor.green,
      );

      final breach = Duty(
        report: DateTime(2026, 9, 28, 10, 0),
        end: DateTime(2026, 9, 28, 22, 1), // 16h01
        type: DutyType.flight,
      );
      expect(
        verifyR17(
          duty: breach,
          standbyStart: standbyStart,
          isIntercontinental: false,
        ).color,
        RuleColor.red,
      );
    });

    test(
        'Continental, duty enters the 0100-0629 window: 13h00 complies, '
        '13h01 does not', () {
      final standbyStart = DateTime(2026, 9, 28, 13, 0);
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 23, 0),
        end: DateTime(2026, 9, 29, 2, 0), // 13h from standby start, ends 0200
        type: DutyType.flight,
      );
      expect(
        verifyR17(
          duty: compliant,
          standbyStart: standbyStart,
          isIntercontinental: false,
        ).color,
        RuleColor.green,
      );

      final breach = Duty(
        report: DateTime(2026, 9, 28, 23, 0),
        end: DateTime(2026, 9, 29, 2, 1), // 13h01
        type: DutyType.flight,
      );
      expect(
        verifyR17(
          duty: breach,
          standbyStart: standbyStart,
          isIntercontinental: false,
        ).color,
        RuleColor.red,
      );
    });

    test('Intercontinental, not extended: 14h00 complies, 14h01 does not',
        () {
      final standbyStart = DateTime(2026, 9, 28, 8, 0);
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 12, 0),
        end: DateTime(2026, 9, 28, 22, 0), // 14h
        type: DutyType.flight,
      );
      expect(
        verifyR17(
          duty: compliant,
          standbyStart: standbyStart,
          isIntercontinental: true,
        ).color,
        RuleColor.green,
      );

      final breach = Duty(
        report: DateTime(2026, 9, 28, 12, 0),
        end: DateTime(2026, 9, 28, 22, 1), // 14h01
        type: DutyType.flight,
      );
      expect(
        verifyR17(
          duty: breach,
          standbyStart: standbyStart,
          isIntercontinental: true,
        ).color,
        RuleColor.red,
      );
    });

    test(
        'Intercontinental, extended duty with no extended duty in the '
        'preceding 8 weeks: the max grows to 15h', () {
      final standbyStart = DateTime(2026, 9, 28, 8, 0);
      final compliant = Duty(
        report: DateTime(2026, 9, 28, 12, 0),
        end: DateTime(2026, 9, 28, 23, 0), // 15h
        type: DutyType.flight,
      );
      expect(
        verifyR17(
          duty: compliant,
          standbyStart: standbyStart,
          isIntercontinental: true,
          isExtendedDuty: true,
          operatedExtendedDutyInPrior8Weeks: false,
        ).color,
        RuleColor.green,
      );

      final breach = Duty(
        report: DateTime(2026, 9, 28, 12, 0),
        end: DateTime(2026, 9, 28, 23, 1), // 15h01
        type: DutyType.flight,
      );
      expect(
        verifyR17(
          duty: breach,
          standbyStart: standbyStart,
          isIntercontinental: true,
          isExtendedDuty: true,
          operatedExtendedDutyInPrior8Weeks: false,
        ).color,
        RuleColor.red,
      );
    });

    test(
        'Intercontinental, extended duty but already operated one in the '
        'preceding 8 weeks: the extension is NOT granted, max stays 14h',
        () {
      final standbyStart = DateTime(2026, 9, 28, 8, 0);
      final duty = Duty(
        report: DateTime(2026, 9, 28, 12, 0),
        end: DateTime(2026, 9, 28, 22, 1), // 14h01 — would pass at 15h
        type: DutyType.flight,
      );
      final result = verifyR17(
        duty: duty,
        standbyStart: standbyStart,
        isIntercontinental: true,
        isExtendedDuty: true,
        operatedExtendedDutyInPrior8Weeks: true,
      );
      expect(result.color, RuleColor.red);
    });
  });
}

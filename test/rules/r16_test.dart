import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/max_duty/r14.dart';
import 'package:ialpa_app/rules/a320/max_duty/r15.dart';
import 'package:ialpa_app/rules/a320/max_duty/r16.dart';

void main() {
  group('R-16 — Delayed Flights modifier (3.4.3 / 3.4.4)', () {
    test(
        'Continental, delay under 2h: reference is the actual report time',
        () {
      final rosteredReport = DateTime(2026, 9, 28, 8, 0);
      final actualReport = DateTime(2026, 9, 28, 9, 30); // 1h30 delay
      final reference = effectiveReportTimeForDelay(
        rosteredReport: rosteredReport,
        actualReport: actualReport,
        isIntercontinental: false,
      );
      expect(reference, actualReport);
    });

    test(
        'Continental, delay of 2h or more: reference is rostered report + '
        '2h', () {
      final rosteredReport = DateTime(2026, 9, 28, 8, 0);
      final actualReport = DateTime(2026, 9, 28, 11, 0); // 3h delay
      final reference = effectiveReportTimeForDelay(
        rosteredReport: rosteredReport,
        actualReport: actualReport,
        isIntercontinental: false,
      );
      expect(reference, DateTime(2026, 9, 28, 10, 0)); // rostered + 2h
    });

    test(
        'Intercontinental, delay under 4h: reference is the actual report '
        'time', () {
      final rosteredReport = DateTime(2026, 9, 28, 8, 0);
      final actualReport = DateTime(2026, 9, 28, 11, 30); // 3h30 delay
      final reference = effectiveReportTimeForDelay(
        rosteredReport: rosteredReport,
        actualReport: actualReport,
        isIntercontinental: true,
      );
      expect(reference, actualReport);
    });

    test(
        'Intercontinental, delay of 4h or more: reference is rostered '
        'report + 4h', () {
      final rosteredReport = DateTime(2026, 9, 28, 8, 0);
      final actualReport = DateTime(2026, 9, 28, 14, 0); // 6h delay
      final reference = effectiveReportTimeForDelay(
        rosteredReport: rosteredReport,
        actualReport: actualReport,
        isIntercontinental: true,
      );
      expect(reference, DateTime(2026, 9, 28, 12, 0)); // rostered + 4h
    });

    test('exactly at the threshold counts as "2h/4h or more"', () {
      final rosteredReport = DateTime(2026, 9, 28, 8, 0);
      final actualReportContinental =
          DateTime(2026, 9, 28, 10, 0); // exactly 2h delay
      expect(
        effectiveReportTimeForDelay(
          rosteredReport: rosteredReport,
          actualReport: actualReportContinental,
          isIntercontinental: false,
        ),
        DateTime(2026, 9, 28, 10, 0), // == rostered + 2h in this case
      );

      final actualReportIntercontinental =
          DateTime(2026, 9, 28, 12, 0); // exactly 4h delay
      expect(
        effectiveReportTimeForDelay(
          rosteredReport: rosteredReport,
          actualReport: actualReportIntercontinental,
          isIntercontinental: true,
        ),
        DateTime(2026, 9, 28, 12, 0), // == rostered + 4h in this case
      );
    });

    test(
        'integration with R-14: a long delay gives relief instead of an '
        'automatic breach', () {
      final rosteredReport = DateTime(2026, 9, 28, 8, 0);
      final actualReport = DateTime(2026, 9, 28, 15, 0); // 7h delay
      final duty = Duty(
        report: actualReport,
        end: DateTime(2026, 9, 29, 3, 0), // 12h actual block, entirely in c
        type: DutyType.flight,
      );
      final reference = effectiveReportTimeForDelay(
        rosteredReport: rosteredReport,
        actualReport: actualReport,
        isIntercontinental: false,
      );
      // Without R-16, the counted duty would be the actual block (12h),
      // which would pass. With R-16, both the band selection and the
      // counted duration use the reference time (rostered+2h = 10:00) per
      // 3.4.4, not the actual (heavily delayed) report time. Counted duty
      // = end (03:00) - reference (10:00) = 17h, which exceeds every
      // applicable band's maximum -> red.
      final result = verifyR14(duty: duty, effectiveReportTime: reference);
      expect(result.color, RuleColor.red);
    });

    test(
        'integration with R-15: short delay uses the actual report time, '
        'no relief needed', () {
      final rosteredReport = DateTime(2026, 9, 28, 8, 0);
      final actualReport = DateTime(2026, 9, 28, 9, 0); // 1h delay
      final duty = Duty(
        report: actualReport,
        end: DateTime(2026, 9, 28, 23, 0), // 14h actual block
        type: DutyType.flight,
      );
      final reference = effectiveReportTimeForDelay(
        rosteredReport: rosteredReport,
        actualReport: actualReport,
        isIntercontinental: true,
      );
      final result = verifyR15(duty: duty, effectiveReportTime: reference);
      expect(result.color, RuleColor.green); // 14h == the 14h maximum
    });
  });
}

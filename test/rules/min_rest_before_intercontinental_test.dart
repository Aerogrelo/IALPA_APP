import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a320/rest/min_rest_before_intercontinental.dart';

void main() {
  group('Minimum rest before an Intercontinental duty (3.14.2a)', () {
    // Short previous day's duty (9h, does not exceed the 10h threshold) ->
    // only the general rule applies: duty+2h=11h, the 12h floor governs.
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 15, 0), // 9h
      type: DutyType.flight,
    );

    test('previous duty of 9h: 11h59 rest does NOT comply (red)', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: shortDuty,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    test('previous duty of 9h: 12h00 rest DOES comply (green)', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: shortDuty,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.green);
    });

    // Previous day's duty of 11h (exceeds the 10h threshold) -> the special
    // 15h floor applies; the general formula would give 13h (11+2), but the
    // greater value (15h) governs.
    final dutyOverThreshold = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 17, 0), // 11h
      type: DutyType.flight,
    );

    test(
        'previous duty of 11h: 14h59 rest does NOT comply with the 15h '
        'convenio floor, but meets the 12h EASA floor -> amber (OWC), not '
        'red', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: dutyOverThreshold,
        plannedRest: const Duration(hours: 14, minutes: 59),
      );
      expect(result.color, RuleColor.amber);
    });

    test('previous duty of 11h: 15h00 rest DOES comply (green)', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: dutyOverThreshold,
        plannedRest: const Duration(hours: 15),
      );
      expect(result.color, RuleColor.green);
    });

    // Very long previous day's duty (14h) -> the general formula (14+2=16h)
    // exceeds the special 15h floor, so the general formula governs.
    final veryLongDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 20, 0), // 14h
      type: DutyType.flight,
    );

    test(
        'previous duty of 14h: the general formula (16h) governs, not the '
        '15h floor — but 15h59 still clears the 14h EASA floor, so it is '
        'amber (OWC), not red', () {
      final insufficient = verifyMinRestBeforeIntercontinental(
        previousDayDuty: veryLongDuty,
        plannedRest: const Duration(hours: 15, minutes: 59),
      );
      expect(insufficient.color, RuleColor.amber);

      final sufficient = verifyMinRestBeforeIntercontinental(
        previousDayDuty: veryLongDuty,
        plannedRest: const Duration(hours: 16),
      );
      expect(sufficient.color, RuleColor.green);
    });
  });

  group('EASA floor — amber (OWC) vs red (2026-09-28)', () {
    // Previous day's duty of 11h (exceeds the 10h threshold) -> convenio
    // minimum is 15h (the special floor governs). EASA minimum (at home
    // base) is duty-or-12h = 12h, since 11h < 12h.
    final dutyOverThreshold = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 17, 0), // 11h
      type: DutyType.flight,
    );

    test(
        'real case: 13h47 rest breaches the 15h convenio floor but meets '
        'the 12h EASA floor -> amber (OWC)', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: dutyOverThreshold,
        plannedRest: const Duration(hours: 13, minutes: 47),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('OWC'));
    });

    test('12h00 rest exactly meets the EASA floor -> still amber', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: dutyOverThreshold,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.amber);
    });

    test('11h59 rest breaches both the convenio and the EASA floor -> red',
        () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: dutyOverThreshold,
        plannedRest: const Duration(hours: 11, minutes: 59),
      );
      expect(result.color, RuleColor.red);
    });

    // Previous day's duty of 13h (exceeds 12h) -> EASA floor tracks the
    // duty itself (13h), not the flat 12h.
    final dutyOver12h = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 19, 0), // 13h
      type: DutyType.flight,
    );

    test(
        'when the previous duty exceeds 12h, the EASA floor tracks the '
        'duty length, not a flat 12h', () {
      final justBelow = verifyMinRestBeforeIntercontinental(
        previousDayDuty: dutyOver12h,
        plannedRest: const Duration(hours: 12, minutes: 59), // < 13h
      );
      expect(justBelow.color, RuleColor.red);

      final atFloor = verifyMinRestBeforeIntercontinental(
        previousDayDuty: dutyOver12h,
        plannedRest: const Duration(hours: 13), // == EASA floor
      );
      expect(atFloor.color, RuleColor.amber);
    });
  });

  group('Clause 2.10.6(a) — previous day duty must not start before 06:00 LT '
      '(2026-09-30)', () {
    // A duty that would otherwise be green on rest length alone.
    final shortDuty = Duty(
      report: DateTime(2026, 9, 28, 6, 0),
      end: DateTime(2026, 9, 28, 15, 0), // 9h
      type: DutyType.flight,
    );

    test('report at 05:59 LT breaches 2.10.6(a): downgrades an otherwise '
        'green result to amber', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: shortDuty,
        plannedRest: const Duration(hours: 12), // would be green alone
        previousDayReportLocal: DateTime(2026, 9, 28, 5, 59),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('2.10.6(a)'));
    });

    test('report at exactly 06:00 LT does NOT breach 2.10.6(a): stays '
        'green', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: shortDuty,
        plannedRest: const Duration(hours: 12),
        previousDayReportLocal: DateTime(2026, 9, 28, 6, 0),
      );
      expect(result.color, RuleColor.green);
    });

    test('report before 06:00 LT never improves an already-red result: '
        'still red', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: shortDuty,
        plannedRest: const Duration(hours: 11, minutes: 59), // red alone
        previousDayReportLocal: DateTime(2026, 9, 28, 5, 30),
      );
      expect(result.color, RuleColor.red);
      expect(result.explanation, contains('2.10.6(a)'));
    });

    test('report before 06:00 LT does not change an already-amber result: '
        'still amber, note appended', () {
      final dutyOverThreshold = Duty(
        report: DateTime(2026, 9, 28, 6, 0),
        end: DateTime(2026, 9, 28, 17, 0), // 11h
        type: DutyType.flight,
      );
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: dutyOverThreshold,
        plannedRest: const Duration(hours: 13, minutes: 47), // amber alone
        previousDayReportLocal: DateTime(2026, 9, 28, 5, 0),
      );
      expect(result.color, RuleColor.amber);
      expect(result.explanation, contains('2.10.6(a)'));
    });

    test('omitting previousDayReportLocal skips the check entirely: '
        'unchanged from the rest-length-only result', () {
      final result = verifyMinRestBeforeIntercontinental(
        previousDayDuty: shortDuty,
        plannedRest: const Duration(hours: 12),
      );
      expect(result.color, RuleColor.green);
      expect(result.explanation, isNot(contains('2.10.6(a)')));
    });
  });
}

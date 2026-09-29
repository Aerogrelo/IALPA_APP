import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/models/rule_result.dart';
import 'package:ialpa_app/rules/a330/max_duty/verify_max_duty.dart';

void main() {
  group('A330 — Maximum Flight Duty Time (3.10), two-pilot', () {
    // Report/end times chosen so the duty stays clear of the 0100-0629
    // night window unless a test is specifically about it (see
    // verify_max_duty_test for the A320/321 for why 06:35 is a safe
    // report time to avoid accidentally spilling into the window).
    final safeReport = DateTime(2026, 9, 29, 6, 35);

    Duty dutyOf(Duration d) =>
        Duty(report: safeReport, end: safeReport.add(d), type: DutyType.flight);

    test('normal, not delayed: 12h00 green, 13h00 amber (EASA +2h '
        "discretion), 14h01 red", () {
      expect(
        verifyA330MaxDuty(duty: dutyOf(const Duration(hours: 12))).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(duty: dutyOf(const Duration(hours: 13))).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 14, minutes: 1)),
        ).color,
        RuleColor.red,
      );
    });

    test('eastbound TA, not delayed: 11h00 green, 12h00 amber, 13h01 red',
        () {
      const direction = TransatlanticDirection.eastbound;
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 11)),
          direction: direction,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 12)),
          direction: direction,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 13, minutes: 1)),
          direction: direction,
        ).color,
        RuleColor.red,
      );
    });

    test('through-the-night, not delayed: 11h00 green, 12h00 amber, 13h01 '
        'red', () {
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 11)),
          throughTheNight: true,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 12)),
          throughTheNight: true,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 13, minutes: 1)),
          throughTheNight: true,
        ).color,
        RuleColor.red,
      );
    });

    test('normal, delayed, clear of the night window: 13h00 green '
        '(3.10.1, 12h+1h), 14h00 amber, 15h01 red', () {
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 13)),
          delayed: true,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 14)),
          delayed: true,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 15, minutes: 1)),
          delayed: true,
        ).color,
        RuleColor.red,
      );
    });

    test('eastbound TA, delayed: 12h00 green (3.10.1, 11h+1h), 13h00 '
        'amber, 14h01 red', () {
      const direction = TransatlanticDirection.eastbound;
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 12)),
          delayed: true,
          direction: direction,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 13)),
          delayed: true,
          direction: direction,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 14, minutes: 1)),
          delayed: true,
          direction: direction,
        ).color,
        RuleColor.red,
      );
    });

    test('delayed AND entering the 0100-0629 window as operating pilot: '
        'hard cap of 12h applies even though the normal delayed max would '
        'be 13h — the same 12h30 duty is green clear of the window, but '
        'once shifted to enter it, the 12h hard cap + 2h EASA discretion '
        'still gives amber, and only a genuinely longer duty goes red',
        () {
      final clearOfWindow = Duty(
        report: safeReport,
        end: DateTime(2026, 9, 29, 19, 5), // 12h30, no night-window overlap
        type: DutyType.flight,
      );
      expect(
        verifyA330MaxDuty(duty: clearOfWindow, delayed: true).color,
        RuleColor.green,
      );

      final entersWindowAmber = Duty(
        report: DateTime(2026, 9, 29, 13, 0),
        end: DateTime(2026, 9, 30, 1, 0), // 12h, hard cap is exactly 12h
        type: DutyType.flight,
      );
      // duty.duration == 12h == maximum, so this should still be green —
      // use 13h instead to land inside the +2h discretion (amber) band.
      final entersWindowAmber13h = Duty(
        report: DateTime(2026, 9, 29, 13, 0),
        end: DateTime(2026, 9, 30, 2, 0), // 13h, enters the window, amber
        type: DutyType.flight,
      );
      expect(
        verifyA330MaxDuty(duty: entersWindowAmber, delayed: true).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(duty: entersWindowAmber13h, delayed: true).color,
        RuleColor.amber,
      );

      final entersWindowRed = Duty(
        report: DateTime(2026, 9, 29, 13, 0),
        end: DateTime(2026, 9, 30, 3, 1), // 14h01, beyond 12h + 2h discretion
        type: DutyType.flight,
      );
      expect(
        verifyA330MaxDuty(duty: entersWindowRed, delayed: true).color,
        RuleColor.red,
      );
    });
  });

  group('A330 — Maximum Flight Duty Time (3.10), augmented crew', () {
    final safeReport = DateTime(2026, 9, 29, 6, 35);

    Duty dutyOf(Duration d, {TransatlanticDirection? direction}) => Duty(
          report: safeReport,
          end: safeReport.add(d),
          type: DutyType.flight,
          transatlanticDirection:
              direction ?? TransatlanticDirection.none,
        );

    test('not delayed, no WOCL encroachment: 15h00 green (2.15.3), 16h00 '
        'amber, 17h01 red', () {
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 15)),
          crewType: A330CrewType.augmented,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 16)),
          crewType: A330CrewType.augmented,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 17, minutes: 1)),
          crewType: A330CrewType.augmented,
        ).color,
        RuleColor.red,
      );
    });

    test('delayed, no WOCL encroachment: 17h00 green (3.10.2, 15h+2h), '
        '18h00 amber, 19h01 red', () {
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 17)),
          crewType: A330CrewType.augmented,
          delayed: true,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 18)),
          crewType: A330CrewType.augmented,
          delayed: true,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 19, minutes: 1)),
          crewType: A330CrewType.augmented,
          delayed: true,
        ).color,
        RuleColor.red,
      );
    });

    test('delayed, extension invades WOCL: only +1h applies — 16h00 '
        'green, 17h00 amber, 18h01 red', () {
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 16)),
          crewType: A330CrewType.augmented,
          delayed: true,
          extensionInvadesWocl: true,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 17)),
          crewType: A330CrewType.augmented,
          delayed: true,
          extensionInvadesWocl: true,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 18, minutes: 1)),
          crewType: A330CrewType.augmented,
          delayed: true,
          extensionInvadesWocl: true,
        ).color,
        RuleColor.red,
      );
    });

    test('WOCL reduction, duty starts in the WOCL: 100% of a 1h '
        'encroachment reduces 15h to 14h00 green, 15h00 amber, 16h01 red',
        () {
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 14)),
          crewType: A330CrewType.augmented,
          woclEncroachment: const Duration(hours: 1),
          dutyStartsInWocl: true,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 15)),
          crewType: A330CrewType.augmented,
          woclEncroachment: const Duration(hours: 1),
          dutyStartsInWocl: true,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 16, minutes: 1)),
          crewType: A330CrewType.augmented,
          woclEncroachment: const Duration(hours: 1),
          dutyStartsInWocl: true,
        ).color,
        RuleColor.red,
      );
    });

    test('WOCL reduction, duty ends in / encompasses the WOCL: 50% of a '
        '1h encroachment reduces 15h to 14h30 green, 15h30 amber, 16h31 '
        'red', () {
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 14, minutes: 30)),
          crewType: A330CrewType.augmented,
          woclEncroachment: const Duration(hours: 1),
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 15, minutes: 30)),
          crewType: A330CrewType.augmented,
          woclEncroachment: const Duration(hours: 1),
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 16, minutes: 31)),
          crewType: A330CrewType.augmented,
          woclEncroachment: const Duration(hours: 1),
        ).color,
        RuleColor.red,
      );
    });

    test('no agreed cockpit rest area, westbound, not delayed: 14h00 '
        'green (2.15.4), 15h00 amber, 16h01 red', () {
      const direction = TransatlanticDirection.westbound;
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 14), direction: direction),
          crewType: A330CrewType.augmented,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 15), direction: direction),
          crewType: A330CrewType.augmented,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 16, minutes: 1),
              direction: direction),
          crewType: A330CrewType.augmented,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.red,
      );
    });

    test('no agreed cockpit rest area, eastbound, not delayed: 13h00 '
        'green (2.15.4), 14h00 amber, 15h01 red', () {
      const direction = TransatlanticDirection.eastbound;
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 13), direction: direction),
          crewType: A330CrewType.augmented,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 14), direction: direction),
          crewType: A330CrewType.augmented,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 15, minutes: 1),
              direction: direction),
          crewType: A330CrewType.augmented,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.red,
      );
    });

    test('no agreed cockpit rest area, westbound, delayed: 15h00 green '
        '(3.10.3, 2.15.4 + 1h), 16h00 amber, 17h01 red', () {
      const direction = TransatlanticDirection.westbound;
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 15), direction: direction),
          crewType: A330CrewType.augmented,
          delayed: true,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 16), direction: direction),
          crewType: A330CrewType.augmented,
          delayed: true,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 17, minutes: 1),
              direction: direction),
          crewType: A330CrewType.augmented,
          delayed: true,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.red,
      );
    });

    test('no agreed cockpit rest area, eastbound, delayed: 14h00 green '
        '(3.10.3, 2.15.4 + 1h), 15h00 amber, 16h01 red', () {
      const direction = TransatlanticDirection.eastbound;
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 14), direction: direction),
          crewType: A330CrewType.augmented,
          delayed: true,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 15), direction: direction),
          crewType: A330CrewType.augmented,
          delayed: true,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 16, minutes: 1),
              direction: direction),
          crewType: A330CrewType.augmented,
          delayed: true,
          agreedCockpitRestArea: false,
          direction: direction,
        ).color,
        RuleColor.red,
      );
    });
  });

  group('A330 — Maximum Flight Duty Time (3.10), heavy crew', () {
    final safeReport = DateTime(2026, 9, 29, 6, 35);

    Duty dutyOf(Duration d) =>
        Duty(report: safeReport, end: safeReport.add(d), type: DutyType.flight);

    test('17h00 green (2.15.5), 18h00 amber, 19h01 red — unaffected by '
        '[delayed]', () {
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 17)),
          crewType: A330CrewType.heavy,
        ).color,
        RuleColor.green,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 18)),
          crewType: A330CrewType.heavy,
          delayed: true, // still unaffected: no referenced extension in 3.10
        ).color,
        RuleColor.amber,
      );
      expect(
        verifyA330MaxDuty(
          duty: dutyOf(const Duration(hours: 19, minutes: 1)),
          crewType: A330CrewType.heavy,
          delayed: true,
        ).color,
        RuleColor.red,
      );
    });
  });
}

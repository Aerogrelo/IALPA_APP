import 'package:flutter_test/flutter_test.dart';
import 'package:ialpa_app/models/duty.dart';
import 'package:ialpa_app/rules/a320/max_duty/latest_push_back.dart';

void main() {
  group('estimatedRemainingDutyDuration', () {
    test('adds up all legs plus the 20-minute post-flight margin once', () {
      final duration = estimatedRemainingDutyDuration(
        taxiOutOutbound: const Duration(minutes: 15),
        outboundFlight: const Duration(hours: 2),
        groundTime: const Duration(hours: 1),
        taxiOutReturn: const Duration(minutes: 15),
        returnFlight: const Duration(hours: 2),
      );
      // 15 + 120 + 60 + 15 + 120 + 20 = 350 minutes = 5h50
      expect(duration, const Duration(hours: 5, minutes: 50));
    });

    test('postFlightMargin can be overridden', () {
      final duration = estimatedRemainingDutyDuration(
        taxiOutOutbound: Duration.zero,
        outboundFlight: const Duration(hours: 1),
        groundTime: Duration.zero,
        taxiOutReturn: Duration.zero,
        returnFlight: Duration.zero,
        postFlightMargin: const Duration(minutes: 30),
      );
      expect(duration, const Duration(hours: 1, minutes: 30));
    });
  });

  group('latestPushBackTime', () {
    test(
        'Continental, band-c duty, no delay: finds the latest push-back '
        'exactly filling the 13h maximum', () {
      final report = DateTime(2026, 9, 28, 8, 0);
      final duty = Duty(
        report: report,
        end: report, // placeholder, end is recomputed per candidate
        type: DutyType.flight,
      );
      final remaining = estimatedRemainingDutyDuration(
        taxiOutOutbound: const Duration(minutes: 15),
        outboundFlight: const Duration(hours: 2),
        groundTime: const Duration(hours: 1),
        taxiOutReturn: const Duration(minutes: 15),
        returnFlight: const Duration(hours: 2),
      ); // 5h50

      final latest = latestPushBackTime(
        duty: duty,
        effectiveReportTime: report,
        isIntercontinental: false,
        remainingDutyDuration: remaining,
        earliestPushBack: report,
      );

      // Max allowed duty (band c, 1 sector) = 13h. 13h - 5h50 = 7h10.
      expect(latest, report.add(const Duration(hours: 7, minutes: 10)));
    });

    test(
        'Intercontinental, Eastbound Transatlantic: respects the 12h '
        'maximum', () {
      final report = DateTime(2026, 9, 28, 10, 0);
      final duty = Duty(
        report: report,
        end: report,
        type: DutyType.flight,
        transatlanticDirection: TransatlanticDirection.eastbound,
      );
      final remaining = const Duration(hours: 3); // short remaining leg

      final latest = latestPushBackTime(
        duty: duty,
        effectiveReportTime: report,
        isIntercontinental: true,
        remainingDutyDuration: remaining,
        earliestPushBack: report,
      );

      // Max allowed = 12h. 12h - 3h = 9h.
      expect(latest, report.add(const Duration(hours: 9)));
    });

    test(
        'returns null when even pushing back immediately would already '
        'breach the maximum', () {
      final report = DateTime(2026, 9, 28, 8, 0);
      final duty = Duty(
        report: report,
        end: report,
        type: DutyType.flight,
        transatlanticDirection: TransatlanticDirection.eastbound,
      );
      // 13h remaining, but the Eastbound TA maximum is 12h — even an
      // immediate push-back is already a breach.
      final remaining = const Duration(hours: 13);

      final latest = latestPushBackTime(
        duty: duty,
        effectiveReportTime: report,
        isIntercontinental: true,
        remainingDutyDuration: remaining,
        earliestPushBack: report,
      );

      expect(latest, isNull);
    });

    test(
        'a long delay (R-16 relief) shifts the effective reference time '
        'and therefore the latest push-back', () {
      final rosteredReport = DateTime(2026, 9, 28, 8, 0);
      final actualReport = DateTime(2026, 9, 28, 15, 0); // 7h delay
      // Continental threshold is 2h, so the reference used is
      // rosteredReport + 2h = 10:00, not the actual (15:00) report.
      final reference = DateTime(2026, 9, 28, 10, 0);

      final duty = Duty(
        report: actualReport,
        end: actualReport,
        type: DutyType.flight,
      );
      final remaining = const Duration(hours: 5, minutes: 50);

      final latest = latestPushBackTime(
        duty: duty,
        effectiveReportTime: reference,
        isIntercontinental: false,
        remainingDutyDuration: remaining,
        earliestPushBack: actualReport,
      );

      // Max allowed duty (band c) = 13h counted from the reference
      // (10:00), so the duty must end by 23:00 at the latest, and
      // push-back must be by 23:00 - 5h50 = 17:10.
      expect(latest, DateTime(2026, 9, 28, 17, 10));
    });
  });
}

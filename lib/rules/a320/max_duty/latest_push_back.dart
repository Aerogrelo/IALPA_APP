import '../../../models/duty.dart';
import '../../../models/rule_result.dart';
import 'r14.dart';
import 'r15.dart';

/// Adds up the estimated duration of the remaining operation, from
/// push-back to the end of duty, for use with [latestPushBackTime].
///
/// This is: taxi-out + outbound flight + ground time at the stopover +
/// taxi-out (return) + return flight, plus a fixed [postFlightMargin]
/// (20 minutes by convention) counted once, from the moment the aircraft
/// reaches its final parking position — that time is post-flight and
/// still counts as duty.
///
/// All of these are meant to be editable in the UI, pre-filled with the
/// rostered/scheduled values but adjustable, since real conditions (taxi
/// time, actual flight time) vary from what was planned.
Duration estimatedRemainingDutyDuration({
  required Duration taxiOutOutbound,
  required Duration outboundFlight,
  required Duration groundTime,
  required Duration taxiOutReturn,
  required Duration returnFlight,
  Duration postFlightMargin = const Duration(minutes: 20),
}) {
  return taxiOutOutbound +
      outboundFlight +
      groundTime +
      taxiOutReturn +
      returnFlight +
      postFlightMargin;
}

/// Calculates the latest time the flight can push back (start moving) so
/// that the resulting duty still complies with the maximum flight duty
/// time — R-14 (Continental, 3.11.1) or R-15 (Intercontinental, 3.11.2).
///
/// This is meant to be used once the pilot has already reported: the
/// report time is a known, fixed fact by then, so [effectiveReportTime]
/// (from R-16, clause 3.4) is a fixed input here, not something being
/// solved for. What is unknown is how much longer the operation can still
/// run before it becomes illegal.
///
/// [remainingDutyDuration] is the estimated time from push-back to the end
/// of duty — see [estimatedRemainingDutyDuration].
///
/// [earliestPushBack] is the earliest moment push-back could happen (e.g.
/// now, or the actual report time) — the search starts from there.
///
/// The search checks every [searchStep] (5 minutes by default) across
/// [searchHorizon] (30 hours by default) and returns the latest push-back
/// time that still comes back green from R-14/R-15, reusing those same
/// rule functions rather than re-deriving their band logic here. Returns
/// null if even pushing back at [earliestPushBack] would already breach
/// the maximum.
DateTime? latestPushBackTime({
  required Duty duty,
  required DateTime effectiveReportTime,
  required bool isIntercontinental,
  required Duration remainingDutyDuration,
  required DateTime earliestPushBack,
  Duration stbhPortion = Duration.zero,
  Duration searchHorizon = const Duration(hours: 30),
  Duration searchStep = const Duration(minutes: 5),
}) {
  DateTime? latestCompliant;

  final horizon = earliestPushBack.add(searchHorizon);
  var candidate = earliestPushBack;

  while (!candidate.isAfter(horizon)) {
    final candidateEnd = candidate.add(remainingDutyDuration);
    final candidateDuty = Duty(
      report: duty.report,
      end: candidateEnd,
      type: duty.type,
      sectors: duty.sectors,
      deadheading: duty.deadheading,
      transatlanticDirection: duty.transatlanticDirection,
      timeDifference: duty.timeDifference,
    );

    final result = isIntercontinental
        ? verifyR15(
            duty: candidateDuty,
            stbhPortion: stbhPortion,
            effectiveReportTime: effectiveReportTime,
          )
        : verifyR14(
            duty: candidateDuty,
            stbhPortion: stbhPortion,
            effectiveReportTime: effectiveReportTime,
          );

    if (result.color == RuleColor.green) {
      latestCompliant = candidate;
    }

    candidate = candidate.add(searchStep);
  }

  return latestCompliant;
}

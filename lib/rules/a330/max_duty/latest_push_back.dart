import '../../../models/duty.dart';
import '../../../models/rule_result.dart';
import 'verify_max_duty.dart';

/// A330 — calculates the latest time the flight can push back (start
/// moving) so that the resulting duty still complies with the maximum
/// flight duty time — clause 3.10, via [verifyA330MaxDuty].
///
/// Same search approach as the A320/321 equivalent (`latest_push_back.dart`
/// under `rules/a320/max_duty/`): the report time is already a known, fixed
/// fact by the time this is used (the pilot has reported), so it searches
/// forward from [earliestPushBack] for the latest push-back time that still
/// comes back green from [verifyA330MaxDuty], reusing that rule rather than
/// re-deriving its band logic here.
///
/// [remainingDutyDuration] is the estimated time from push-back to the end
/// of duty (taxi-out + flight + any further legs + a post-flight margin —
/// see `estimatedRemainingDutyDuration` in the A320/321 file, reused as-is
/// since it is not fleet-specific).
///
/// The search checks every [searchStep] (5 minutes by default) across
/// [searchHorizon] (30 hours by default) and returns the latest push-back
/// time that still complies, or null if even pushing back at
/// [earliestPushBack] would already breach the maximum.
DateTime? latestPushBackTimeA330({
  required Duty duty,
  required Duration remainingDutyDuration,
  required DateTime earliestPushBack,
  A330CrewType crewType = A330CrewType.twoPilot,
  bool delayed = false,
  bool agreedCockpitRestArea = true,
  TransatlanticDirection? direction,
  bool throughTheNight = false,
  Duration woclEncroachment = Duration.zero,
  bool dutyStartsInWocl = false,
  bool extensionInvadesWocl = false,
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

    final result = verifyA330MaxDuty(
      duty: candidateDuty,
      crewType: crewType,
      delayed: delayed,
      agreedCockpitRestArea: agreedCockpitRestArea,
      direction: direction,
      throughTheNight: throughTheNight,
      woclEncroachment: woclEncroachment,
      dutyStartsInWocl: dutyStartsInWocl,
      extensionInvadesWocl: extensionInvadesWocl,
    );

    if (result.color == RuleColor.green) {
      latestCompliant = candidate;
    }

    candidate = candidate.add(searchStep);
  }

  return latestCompliant;
}

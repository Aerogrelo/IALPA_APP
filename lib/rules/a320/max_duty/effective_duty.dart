import '../../../models/duty.dart';

/// Computes the flight duty time that counts towards the maximum limits of
/// R-14/R-15 (clause 3.11), applying the adjustments confirmed against the
/// convenio:
///
/// - Only half of a preceding Standby at Home ([stbhPortion]) counts, per
///   3.17.2(c) — as opposed to the 100% that counts for rest-minimum
///   purposes (1.8/1.19), used in Group B.
/// - A preceding Standby at the Airport ([stbaPortion]) counts in FULL, per
///   2.16.1(b) — unlike STBH, there is no 50% reduction. A pilot cannot be
///   on both an STBH and an STBA immediately before the same report, so the
///   two portions are meant to be used one at a time in practice, but both
///   parameters are added here regardless.
/// - When the duty was delayed and [effectiveReportTime] is supplied (from
///   [effectiveReportTimeForDelay], R-16, clause 3.4), the counted duration
///   runs from that reference time instead of the duty's actual report
///   time. This is what gives the pilot relief for long delays notified in
///   advance: once past the 2h/4h threshold, extra delay beyond the
///   threshold is the only part that keeps counting against the duty.
Duration effectiveFlightDutyTime(
  Duty duty, {
  Duration stbhPortion = Duration.zero,
  Duration stbaPortion = Duration.zero,
  DateTime? effectiveReportTime,
}) {
  final baseDuration = effectiveReportTime != null
      ? duty.end.difference(effectiveReportTime)
      : duty.duration;
  final halvedStbh = Duration(minutes: stbhPortion.inMinutes ~/ 2);
  return baseDuration + halvedStbh + stbaPortion;
}

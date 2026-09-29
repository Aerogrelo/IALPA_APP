/// R-16 — Delayed Flights modifier for Maximum Flight Duty Time
/// (clause 3.4.3 Intercontinental / 3.4.4 Continental of the A320/321
/// Working Conditions).
///
/// When a pilot is advised of a delay before commencing a flight duty, the
/// reference report time used to calculate maximum flight duty time (in
/// [verifyR14]/[verifyR15], via [effectiveFlightDutyTime]) depends on how
/// long the delay is:
/// - Continental (3.4.4): delay < 2h → the reference is the actual report
///   time. Delay >= 2h → the reference is the rostered report time + 2h.
/// - Intercontinental (3.4.3): delay < 4h → the reference is the actual
///   report time. Delay >= 4h → the reference is the rostered report time
///   + 4h.
///
/// This is a modifier, not a standalone pass/fail rule: it does not return
/// a [RuleResult] itself. It computes the reference report time to feed
/// into R-14/R-15, exactly as R-13 (3.14.4) modifies the rest-calculation
/// reference point rather than defining its own minimum.
DateTime effectiveReportTimeForDelay({
  required DateTime rosteredReport,
  required DateTime actualReport,
  required bool isIntercontinental,
}) {
  final threshold =
      isIntercontinental ? const Duration(hours: 4) : const Duration(hours: 2);
  final delay = actualReport.difference(rosteredReport);

  if (delay < threshold) {
    return actualReport;
  }
  return rosteredReport.add(threshold);
}

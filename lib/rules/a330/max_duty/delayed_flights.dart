/// A330 — Delayed Flights modifier for Maximum Flight Duty Time (clauses
/// 3.7 Intercontinental / 3.8 Continental of the Widebody Consolidated
/// Working Conditions 2025).
///
/// Identical formula to R-16 of the A320/321 (3.4.3/3.4.4): when a pilot is
/// advised of a delay before commencing a flight duty, the reference report
/// time used to calculate maximum flight duty time (in [verifyA330MaxDuty])
/// depends on how long the delay is:
/// - Continental (3.8): delay < 2h → the reference is the actual report
///   time. Delay >= 2h → the reference is the rostered report time + 2h.
/// - Intercontinental (3.7): delay < 4h → the reference is the actual
///   report time. Delay >= 4h → the reference is the rostered report time
///   + 4h.
///
/// ASSUMPTION FLAGGED FOR CONFIRMATION: which clause number is
/// Intercontinental and which is Continental (3.7 vs 3.8) is assumed to
/// follow the same order as the A320/321 (3.4.3 Intercontinental before
/// 3.4.4 Continental) — this is a labelling detail only, it does not change
/// the 2h/4h thresholds themselves, which were verified against the source
/// PDF as identical to R-16.
///
/// This is a modifier, not a standalone pass/fail rule: it does not return
/// a [RuleResult] itself. It computes the reference report time to feed
/// into [verifyA330MaxDuty] (via its `duty` parameter's report time).
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

import '../../../models/rule_result.dart';

/// R-03 — Change to a Standby Duty (clause 3.2.3(c) of the A320/321
/// Working Conditions).
///
/// When the roster duty is changed to a standby duty, the standby duty
/// shall fall within plus or minus one (+/-1) hour of the original
/// flight duty's report time.
///
/// A breach of this clause can never be red on its own — EASA does not
/// regulate scheduling flexibility (same reasoning as R-01/R-02).
RuleResult verifyR03({
  required DateTime originalFlightReport,
  required DateTime newStandbyStart,
}) {
  final earliest = originalFlightReport.subtract(const Duration(hours: 1));
  final latest = originalFlightReport.add(const Duration(hours: 1));

  if (!newStandbyStart.isBefore(earliest) &&
      !newStandbyStart.isAfter(latest)) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.3(c)',
      explanation: 'The new standby start is within ±1h of the original '
          'flight duty report time.',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.3(c)',
    explanation: 'The new standby start is more than ±1h from the '
        'original flight duty report time. Breaches the agreement, not '
        'EASA.',
  );
}

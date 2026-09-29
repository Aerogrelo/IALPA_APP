import '../../../models/rule_result.dart';

/// A330 — Change of Duty by the Airline, at Base, on the day of operation
/// (clause 3.2.4 of the Widebody Consolidated Working Conditions 2025).
///
/// "At Base, on the day of operation, a pilot can have their roster flight
/// duties changed to different flight duties provided that the check in
/// time is not more than one hour earlier or four hours later. If the
/// change is to an augmented crew operation, then it cannot be more than
/// one hour earlier or two hours later."
///
/// Colour design (confirmed with Elena 29/09): clause 3.2 is a purely
/// contractual change-of-duty rule — EASA has no opinion on how much notice
/// or leeway the airline must give for a schedule change, only on the
/// resulting rest/duty-time limits (checked separately by Group B/D). So a
/// breach of 3.2 on its own is always OWC (amber), never red.
RuleResult verifyChangeAtBaseDayOfOperation({
  required DateTime originalReport,
  required DateTime newReport,
  bool changeToAugmentedCrewOperation = false,
}) {
  final earlierLimit = const Duration(hours: 1);
  final laterLimit = changeToAugmentedCrewOperation
      ? const Duration(hours: 2)
      : const Duration(hours: 4);

  final earliestAllowed = originalReport.subtract(earlierLimit);
  final latestAllowed = originalReport.add(laterLimit);

  final withinWindow =
      !newReport.isBefore(earliestAllowed) && !newReport.isAfter(latestAllowed);

  final suffix = changeToAugmentedCrewOperation
      ? ' (change to an augmented crew operation: max 1h earlier / 2h later)'
      : ' (max 1h earlier / 4h later)';

  if (withinWindow) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.4 (change of duty, at base, day of operation)',
      explanation: 'New check-in time is within the allowed window$suffix.',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.4 (change of duty, at base, day of operation)',
    explanation: 'OWC (Outside Working Conditions). New check-in time '
        'falls outside the allowed window$suffix — breaches the '
        'agreement, but this is a contractual limit only (EASA has no '
        'separate rule on this), so it is not by itself a legal breach. '
        'Requires Blue Sheet compensation / pilot consent.',
  );
}

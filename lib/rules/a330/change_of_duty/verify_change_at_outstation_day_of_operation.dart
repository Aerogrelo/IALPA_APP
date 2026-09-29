import '../../../models/rule_result.dart';

/// A330 — Change of Duty by the Airline, at an Outstation, on the day of
/// operation (clause 3.2.9 of the Widebody Consolidated Working Conditions
/// 2025).
///
/// "At an Outstation, on the day of operation, for operational reasons a
/// pilot can have their rostered flight duties changed to different
/// duties provided that the check in time is not more than one hour
/// earlier or four hours later. If the pilot has already reported, then
/// the duty can only be changed to a maximum of two hours [later]."
///
/// ASSUMPTION FLAGGED: the "maximum of two hours" for an already-reported
/// pilot is read as a later-only extension (mirrors 3.2.6's "cannot be
/// more than two hours later" at base), not a symmetric ±2h window —
/// the clause text doesn't repeat "earlier or later" for this part.
///
/// Colour: always amber on breach, never red — see
/// `verify_change_at_base_day_of_operation.dart` for why.
RuleResult verifyChangeAtOutstationDayOfOperation({
  required DateTime originalReport,
  required DateTime newReport,
  bool alreadyReported = false,
}) {
  if (alreadyReported) {
    const maxLater = Duration(hours: 2);
    final latestAllowed = originalReport.add(maxLater);

    if (!newReport.isAfter(latestAllowed)) {
      return RuleResult(
        color: RuleColor.green,
        clause: '3.2.9 (change of duty, at outstation, already reported)',
        explanation: 'Change is no more than 2h later than the duty '
            'already reported for.',
      );
    }

    return RuleResult(
      color: RuleColor.amber,
      clause: '3.2.9 (change of duty, at outstation, already reported)',
      explanation: 'OWC (Outside Working Conditions). Change is more '
          'than 2h later than the duty already reported for — breaches '
          'the agreement, but this is a contractual limit only. Requires '
          'Blue Sheet compensation / pilot consent.',
    );
  }

  const earlierLimit = Duration(hours: 1);
  const laterLimit = Duration(hours: 4);
  final earliestAllowed = originalReport.subtract(earlierLimit);
  final latestAllowed = originalReport.add(laterLimit);

  final withinWindow =
      !newReport.isBefore(earliestAllowed) && !newReport.isAfter(latestAllowed);

  if (withinWindow) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.9 (change of duty, at outstation, day of operation)',
      explanation: 'New check-in time is within the allowed window (max '
          '1h earlier / 4h later).',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.9 (change of duty, at outstation, day of operation)',
    explanation: 'OWC (Outside Working Conditions). New check-in time '
        'falls outside the allowed window (max 1h earlier / 4h later) — '
        'breaches the agreement, but this is a contractual limit only. '
        'Requires Blue Sheet compensation / pilot consent.',
  );
}

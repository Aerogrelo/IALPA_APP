import '../../../models/rule_result.dart';

/// R-07 — Change of Duty, Intercontinental, day of operation, at
/// Outstation (clause 3.2.4(f) of the A320/321 Working Conditions).
///
/// At an Outstation, on the day of operation, for operational reasons, a
/// pilot can have his rostered flight duties changed to different duties
/// provided the check-in time is not more than 1h earlier or 4h later —
/// unless the pilot has already reported for duty, in which case the
/// change cannot be for more than 2h later.
///
/// Identical structure to the A330's equivalent rule (3.2.9,
/// `verifyChangeAtOutstationDayOfOperation`) — same interpretation
/// assumption applies: [alreadyReported] is read as also removing the
/// -1h earlier allowance (the source text does not explicitly say),
/// since a pilot who has already reported cannot un-report earlier.
///
/// A breach of this clause can never be red on its own — EASA does not
/// regulate scheduling flexibility (same reasoning as R-01 through R-06).
RuleResult verifyR07({
  required DateTime originalReport,
  required DateTime newReport,
  bool alreadyReported = false,
}) {
  if (alreadyReported) {
    final latest = originalReport.add(const Duration(hours: 2));
    if (!newReport.isAfter(latest)) {
      return RuleResult(
        color: RuleColor.green,
        clause: '3.2.4(f)',
        explanation: 'Already reported: new check-in is no more than 2h '
            'later than the original.',
      );
    }
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.2.4(f)',
      explanation: 'Already reported: new check-in is more than 2h '
          'later than the original. Breaches the agreement, not EASA.',
    );
  }

  final earliest = originalReport.subtract(const Duration(hours: 1));
  final latest = originalReport.add(const Duration(hours: 4));

  if (!newReport.isBefore(earliest) && !newReport.isAfter(latest)) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.4(f)',
      explanation: 'New check-in is no more than 1h earlier or 4h later '
          'than the original.',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.4(f)',
    explanation: 'New check-in is outside the -1h/+4h window. Breaches '
        'the agreement, not EASA.',
  );
}

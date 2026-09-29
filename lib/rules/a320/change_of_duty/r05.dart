import '../../../models/rule_result.dart';

/// R-05 — Change of Duty, Intercontinental, day of operation, at Base
/// (clause 3.2.4(b) of the A320/321 Working Conditions).
///
/// At Base, on the day, for operational reasons, a pilot can have his
/// rostered flight duty changed to a different flight duty provided the
/// report time is not more than 1h earlier or 2h later than the original.
///
/// A breach of this clause can never be red on its own — EASA does not
/// regulate scheduling flexibility (same reasoning as R-01 through R-04).
RuleResult verifyR05({
  required DateTime originalReport,
  required DateTime newReport,
}) {
  final earliest = originalReport.subtract(const Duration(hours: 1));
  final latest = originalReport.add(const Duration(hours: 2));

  if (!newReport.isBefore(earliest) && !newReport.isAfter(latest)) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.4(b)',
      explanation: 'New report is no more than 1h earlier or 2h later '
          'than the original duty.',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.4(b)',
    explanation: 'New report is outside the -1h/+2h day-of-operation '
        'window. Breaches the agreement, not EASA.',
  );
}

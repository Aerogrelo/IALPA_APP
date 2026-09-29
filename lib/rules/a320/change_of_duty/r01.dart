import '../../../models/rule_result.dart';

/// R-01 — Change of Duty, Continental, day of operation, at Base
/// (clause 3.2.3(a) of the A320/321 Working Conditions).
///
/// On the day of operation a pilot's duty may be changed to another duty
/// provided the new duty reports not more than 1h earlier than the
/// original AND finishes not more than 2h later than the original. Both
/// conditions must hold — this differs from the A330's equivalent rule,
/// which only checks a single report-time window; here the convenio
/// separately bounds the report time and the finish time.
///
/// A change that finishes 61-120 minutes later than the original still
/// complies with this clause, but triggers an OWC payment (0.19% of basic
/// salary) — noted in the explanation, not affecting the color.
///
/// Since EASA does not regulate the airline's scheduling flexibility, a
/// breach of this clause can never be red on its own — only green or
/// amber (confirmed with Elena for the A330 equivalent, 29/09, applied
/// here for consistency across fleets).
RuleResult verifyR01({
  required DateTime originalReport,
  required DateTime originalFinish,
  required DateTime newReport,
  required DateTime newFinish,
}) {
  final earliestReport =
      originalReport.subtract(const Duration(hours: 1));
  final latestFinish = originalFinish.add(const Duration(hours: 2));

  final reportOk = !newReport.isBefore(earliestReport);
  final finishOk = !newFinish.isAfter(latestFinish);

  if (reportOk && finishOk) {
    final delay = newFinish.difference(originalFinish);
    final owcNote = delay > const Duration(hours: 1) && delay <= const Duration(hours: 2)
        ? ' An OWC payment (0.19%) applies for finishing '
            '${delay.inMinutes} minutes later than the original duty.'
        : '';
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.3(a)',
      explanation: 'New report is no more than 1h earlier and new finish '
          'no more than 2h later than the original duty.$owcNote',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.3(a)',
    explanation: 'The change of duty exceeds the day-of-operation window '
        '(report not more than 1h earlier, finish not more than 2h '
        'later than the original duty). Breaches the agreement, not EASA.',
  );
}

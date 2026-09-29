import '../../../models/rule_result.dart';

/// A330 — Change of Duty by the Airline, at Base, after the pilot has
/// reported for the flight duty (clause 3.2.6 of the Widebody Consolidated
/// Working Conditions 2025).
///
/// "At Base, when a pilot has reported for a flight duty, the change
/// cannot be more than two hours later."
///
/// Read as: once reported, the airline may push the duty's finish time
/// later, but not by more than 2h beyond what the pilot had reported for.
///
/// Colour: always amber on breach, never red — see
/// `verify_change_at_base_day_of_operation.dart` for why.
RuleResult verifyChangeAfterReportingAtBase({
  required DateTime originalFinish,
  required DateTime newFinish,
}) {
  const maxLater = Duration(hours: 2);
  final latestAllowed = originalFinish.add(maxLater);

  if (!newFinish.isAfter(latestAllowed)) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.6 (change of duty, at base, after reporting)',
      explanation: 'New finish time is no more than 2h later than the '
          'duty originally reported for.',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.6 (change of duty, at base, after reporting)',
    explanation: 'OWC (Outside Working Conditions). New finish time is '
        'more than 2h later than the duty originally reported for — '
        'breaches the agreement, but this is a contractual limit only. '
        'Requires Blue Sheet compensation / pilot consent.',
  );
}

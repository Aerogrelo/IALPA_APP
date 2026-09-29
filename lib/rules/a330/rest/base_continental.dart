import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// A330 — Minimum rest at base following a Continental duty (clause 3.13 of
/// the Widebody Consolidated Working Conditions 2025). Identical formula to
/// R-06 of the A320/321: duty real +2h, floor 12h.
///
/// EASA-equivalent floor (added 29/09): same as R-06 — at home base, EASA
/// floor = `max(previous duty, 12h)`, with no "+2h" component.
RuleResult verifyA330BaseContinentalRest({
  required Duty previousDuty,
  required Duration plannedRest,
}) {
  const absoluteMinimum = Duration(hours: 12);
  const offset = Duration(hours: 2);

  final formulaMinimum = previousDuty.duration + offset;
  final minimumRest =
      formulaMinimum > absoluteMinimum ? formulaMinimum : absoluteMinimum;

  final easaMinimum = previousDuty.duration > absoluteMinimum
      ? previousDuty.duration
      : absoluteMinimum;
  const easaReference = 'EASA ORO.FTL.235 / CS FTL.1.235 (at home base): '
      'minimum rest = the preceding duty period or 12h, whichever is '
      'greater.';

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.13 (base, continental)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)}.',
      easaReference: easaReference,
    );
  }

  if (plannedRest >= easaMinimum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.13 (base, continental)',
      explanation: 'OWC (Outside Working Conditions). Planned rest of '
          '${_fmt(plannedRest)} does NOT meet the convenio minimum of '
          '${_fmt(minimumRest)}, but it DOES meet the EASA minimum of '
          '${_fmt(easaMinimum)} — so it breaches the agreement but is '
          'legal. Requires Blue Sheet compensation / pilot consent.',
      easaReference: easaReference,
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: '3.13 (base, continental)',
    explanation: 'Planned rest of ${_fmt(plannedRest)} does NOT meet the '
        'required minimum of ${_fmt(minimumRest)}, and it also falls short '
        'of the EASA minimum of ${_fmt(easaMinimum)} — this is not just a '
        'breach of the agreement, it is illegal under EASA.',
    easaReference: easaReference,
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

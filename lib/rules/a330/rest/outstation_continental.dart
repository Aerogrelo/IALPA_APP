import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// A330 — Minimum rest at an outstation following a Continental duty
/// (clause 3.13 of the Widebody Consolidated Working Conditions 2025).
/// Identical formula to R-07 of the A320/321: duty real +2h, floor 11h.
///
/// EASA-equivalent floor (added 29/09): same as R-07 — away from base, EASA
/// floor = `max(previous duty, 10h)` (plus an 8h guaranteed sleep window,
/// not modelled separately). Unlike the base rules, there is margin here
/// even with a short previous duty.
RuleResult verifyA330OutstationContinentalRest({
  required Duty previousDuty,
  required Duration plannedRest,
}) {
  const absoluteMinimum = Duration(hours: 11);
  const offset = Duration(hours: 2);

  final formulaMinimum = previousDuty.duration + offset;
  final minimumRest =
      formulaMinimum > absoluteMinimum ? formulaMinimum : absoluteMinimum;

  const easaFloor = Duration(hours: 10);
  final easaMinimum = previousDuty.duration > easaFloor
      ? previousDuty.duration
      : easaFloor;
  const easaReference = 'EASA ORO.FTL.235 / CS FTL.1.235 (away from base): '
      'minimum rest = the preceding duty period or 10h, whichever is '
      'greater, plus an 8h guaranteed sleep opportunity (not modelled '
      'separately here).';

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.13 (outstation, continental)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)}.',
      easaReference: easaReference,
    );
  }

  if (plannedRest >= easaMinimum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.13 (outstation, continental)',
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
    clause: '3.13 (outstation, continental)',
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

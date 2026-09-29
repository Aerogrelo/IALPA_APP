import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// R-06 — Minimum rest at Base following a Continental/Canary Islands duty
/// (clause 3.14.1(a) of the A320/321 Working Conditions).
///
/// EASA-equivalent floor (added 2026-09-28, same pattern confirmed with
/// Elena for `min_rest_before_intercontinental.dart`): at home base, EASA
/// (ORO.FTL.235 / CS FTL.1.235) requires the GREATER of the preceding duty
/// period or 12h — with no "+2h" component, so it is more lenient than the
/// convenio's own formula. If planned rest breaches the convenio minimum
/// but still meets this EASA floor, the result is AMBER (OWC) rather than
/// RED.
RuleResult verifyR06({
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
      clause: '3.14.1(a)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)}.',
      easaReference: easaReference,
    );
  }

  if (plannedRest >= easaMinimum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.14.1(a)',
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
    clause: '3.14.1(a)',
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

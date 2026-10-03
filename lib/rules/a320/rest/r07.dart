import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// R-07 — Minimum rest at an Outstation following a Continental/Canary
/// Islands duty (clause 3.14.1(b) of the A320/321 Working Conditions).
///
/// EASA-equivalent floor (added 2026-09-28): away from home base, EASA
/// (ORO.FTL.235 / CS FTL.1.235) requires the GREATER of the preceding duty
/// period or 10h, PLUS a guaranteed 8h sleep opportunity within that rest
/// period. This model only checks the numeric floor (10h) — it does not
/// track interruptions within the rest period, so the 8h guaranteed sleep
/// opportunity is a caveat not fully represented here. If planned rest
/// breaches the agreement minimum (11h) but still meets the 10h EASA floor,
/// the result is AMBER (OWC) rather than RED.
RuleResult verifyR07({
  required Duty previousDuty,
  required Duration plannedRest,
}) {
  const absoluteMinimum = Duration(hours: 11);
  const offset = Duration(hours: 2);
  const formulaDetail = 'actual duty + 2h or 11h, whichever is greater';

  final formulaMinimum = previousDuty.duration + offset;
  final minimumRest =
      formulaMinimum > absoluteMinimum ? formulaMinimum : absoluteMinimum;

  const easaAbsoluteMinimum = Duration(hours: 10);
  final easaMinimum = previousDuty.duration > easaAbsoluteMinimum
      ? previousDuty.duration
      : easaAbsoluteMinimum;
  const easaReference = 'EASA ORO.FTL.235 / CS FTL.1.235 (away from home '
      'base): minimum rest = the preceding duty period or 10h, whichever '
      'is greater, plus a guaranteed 8h sleep opportunity within that '
      'rest period (not separately modelled here).';

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.14.1(b)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)} ($formulaDetail).',
      easaReference: easaReference,
    );
  }

  if (plannedRest >= easaMinimum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.14.1(b)',
      explanation: 'OWC (Outside Working Conditions). Planned rest of '
          '${_fmt(plannedRest)} does NOT meet the agreement minimum of '
          '${_fmt(minimumRest)} ($formulaDetail), but it DOES meet the '
          'EASA minimum of ${_fmt(easaMinimum)} — so it breaches the '
          'agreement but is legal. Requires Blue Sheet compensation / '
          'pilot consent.',
      easaReference: easaReference,
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: '3.14.1(b)',
    explanation: 'Planned rest of ${_fmt(plannedRest)} does NOT meet the '
        'required minimum of ${_fmt(minimumRest)} ($formulaDetail), and it '
        'also falls short of the EASA minimum of ${_fmt(easaMinimum)} — '
        'this is not just a breach of the agreement, it is illegal under '
        'EASA.',
    easaReference: easaReference,
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

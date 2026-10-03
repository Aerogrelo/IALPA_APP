import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// R-08 — Minimum rest following a through-the-night duty, or any duty
/// delayed such that it encompasses 0330 (clause 3.14.1(c) of the A320/321
/// Working Conditions).
///
/// EASA-equivalent floor (added 2026-09-28): confirmed with Elena that these
/// through-the-night duties are always at home base, so the same EASA floor
/// used for R-06/R-11 applies here — EASA (ORO.FTL.235 / CS FTL.1.235) does
/// not set a separate rest floor for a through-the-night duty; the
/// disruption is addressed on the FDP side (WOCL), not the rest side, so the
/// ordinary at-home-base floor (the preceding duty or 12h, whichever is
/// greater) is the correct reference. If planned rest breaches the agreement
/// minimum but still meets this EASA floor, the result is AMBER (OWC)
/// rather than RED.
RuleResult verifyR08({
  required Duty previousDuty,
  required Duration plannedRest,
}) {
  const absoluteMinimum = Duration(hours: 14);
  const offset = Duration(hours: 4);
  const formulaDetail = 'actual duty + 4h or 14h, whichever is greater';

  final formulaMinimum = previousDuty.duration + offset;
  final minimumRest =
      formulaMinimum > absoluteMinimum ? formulaMinimum : absoluteMinimum;

  const easaFloor = Duration(hours: 12);
  final easaMinimum = previousDuty.duration > easaFloor
      ? previousDuty.duration
      : easaFloor;
  const easaReference = 'EASA ORO.FTL.235 / CS FTL.1.235 (at home base): '
      'minimum rest = the preceding duty period or 12h, whichever is '
      'greater. EASA does not set a separate floor for a through-the-night '
      'duty.';

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.14.1(c)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)} ($formulaDetail).',
      easaReference: easaReference,
    );
  }

  if (plannedRest >= easaMinimum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.14.1(c)',
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
    clause: '3.14.1(c)',
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

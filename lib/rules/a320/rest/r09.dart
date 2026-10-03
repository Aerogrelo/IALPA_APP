import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// R-09 — Minimum rest following a westbound transatlantic duty (clause
/// 3.14.2(b) of the A320/321 Working Conditions). The offset added to the
/// duty duration is the time difference of the previous duty, not a fixed
/// value.
///
/// EASA-equivalent floor (added 2026-09-28): a westbound transatlantic duty
/// brings the pilot back to home base, and EASA's rest requirement at home
/// base does not add anything for time-zone difference — confirmed with
/// Elena to use the same floor as R-06/R-11/R-08 (the preceding duty or
/// 12h, whichever is greater), with no time-difference term. This leaves a
/// wide amber band here, since the agreement's own 18h floor (plus the
/// time-difference term) is considerably stricter than EASA's plain
/// at-base floor.
RuleResult verifyR09({
  required Duty previousDuty,
  required Duration plannedRest,
}) {
  const absoluteMinimum = Duration(hours: 18);

  final formulaMinimum = previousDuty.duration + previousDuty.timeDifference;
  final formulaDetail = 'actual duty + time difference '
      '(${_fmt(previousDuty.timeDifference)}) or 18h, whichever is greater';
  final minimumRest =
      formulaMinimum > absoluteMinimum ? formulaMinimum : absoluteMinimum;

  const easaFloor = Duration(hours: 12);
  final easaMinimum = previousDuty.duration > easaFloor
      ? previousDuty.duration
      : easaFloor;
  const easaReference = 'EASA ORO.FTL.235 / CS FTL.1.235 (at home base): '
      'minimum rest = the preceding duty period or 12h, whichever is '
      'greater. EASA does not add a time-zone-difference term for rest '
      'taken at home base.';

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.14.2(b)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)} ($formulaDetail).',
      easaReference: easaReference,
    );
  }

  if (plannedRest >= easaMinimum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.14.2(b)',
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
    clause: '3.14.2(b)',
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

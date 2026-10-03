import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// A330 — Minimum rest following a westbound intercontinental duty (clause
/// 3.13.2 of the Widebody Consolidated Working Conditions 2025). Same
/// formula as R-09 of the A320/321: duty real + time difference, floor 18h.
///
/// EASA-equivalent floor (added 29/09): confirmed with Elena that this rest
/// is always taken at home base, on return. Same pattern as R-09: EASA
/// floor = `max(previous duty, 12h)`, with no time-difference term.
RuleResult verifyA330PostIntercontinentalWestboundRest({
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
      clause: '3.13.2',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)} ($formulaDetail).',
      easaReference: easaReference,
    );
  }

  if (plannedRest >= easaMinimum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.13.2',
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
    clause: '3.13.2',
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

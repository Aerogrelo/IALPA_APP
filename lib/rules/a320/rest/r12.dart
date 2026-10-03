import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// R-12 — Minimum rest following completion of a Standby duty (clause 3.17.5
/// of the A320/321 Working Conditions).
///
/// - If no duty was assigned during the standby: minimum rest = 12h.
/// - If a duty was assigned: minimum rest = the greater of (actual duty +
///   2h) and 12h (same formula as R-06).
///
/// EASA-equivalent floor (added 2026-09-28): a standby at home (STBH) is by
/// definition at home base, so this uses the same EASA at-home-base floor
/// as R-06/R-11 — the preceding duty period or 12h, whichever is greater.
/// When no duty was assigned, the agreement minimum (12h) already equals
/// the EASA floor, so there is no amber zone in that case.
RuleResult verifyR12({
  required Duty? dutyAssignedOnStandby,
  required Duration plannedRest,
}) {
  const absoluteMinimum = Duration(hours: 12);

  final Duration minimumRest;
  final Duration easaMinimum;
  final String formulaDetail;

  if (dutyAssignedOnStandby == null) {
    minimumRest = absoluteMinimum;
    easaMinimum = absoluteMinimum;
    formulaDetail = 'no duty was assigned during the standby, minimum 12h';
  } else {
    final formulaMinimum =
        dutyAssignedOnStandby.duration + const Duration(hours: 2);
    minimumRest =
        formulaMinimum > absoluteMinimum ? formulaMinimum : absoluteMinimum;
    easaMinimum = dutyAssignedOnStandby.duration > absoluteMinimum
        ? dutyAssignedOnStandby.duration
        : absoluteMinimum;
    formulaDetail = 'duty assigned, actual duty + 2h or 12h, whichever is '
        'greater';
  }

  const easaReference = 'EASA ORO.FTL.235 / CS FTL.1.235 (at home base): '
      'minimum rest = the preceding duty period or 12h, whichever is '
      'greater.';

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.17.5',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)} ($formulaDetail).',
      easaReference: easaReference,
    );
  }

  if (plannedRest >= easaMinimum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.17.5',
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
    clause: '3.17.5',
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

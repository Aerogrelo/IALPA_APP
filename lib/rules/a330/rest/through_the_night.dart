import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// A330 — Minimum rest following a through-the-night duty (clause 3.13 of
/// the Widebody Consolidated Working Conditions 2025). Identical formula to
/// R-08 of the A320/321: duty real +4h, floor 14h.
///
/// EASA-equivalent floor (added 29/09): confirmed with Elena this duty is
/// always at home base (same as R-08) — EASA does not set a separate floor
/// for a through-the-night duty, so the ordinary at-base floor applies:
/// `max(previous duty, 12h)`.
RuleResult verifyA330ThroughTheNightRest({
  required Duty previousDuty,
  required Duration plannedRest,
}) {
  const absoluteMinimum = Duration(hours: 14);
  const offset = Duration(hours: 4);

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
      clause: '3.13 (through-the-night)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)}.',
      easaReference: easaReference,
    );
  }

  if (plannedRest >= easaMinimum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.13 (through-the-night)',
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
    clause: '3.13 (through-the-night)',
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

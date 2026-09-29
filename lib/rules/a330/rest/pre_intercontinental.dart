import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// A330 — Minimum rest before an intercontinental duty (clause 3.13 of the
/// Widebody Consolidated Working Conditions 2025).
///
/// Unlike the A320/321 pre-intercontinental rule (which is a formula, duty
/// anterior +2h with a 12h/15h floor), the A330 clause gives flat values:
/// 15h, reduced to 13h when the rest is preceded by a standby duty.
///
/// EASA-equivalent floor (added 29/09): confirmed with Elena that, like the
/// A320/321, this rest is always taken at home base. EASA floor =
/// `max(previous duty, 12h)` — same pattern as R-06/R-11 and the A320/321
/// pre-intercontinental rule. [previousDuty] is optional because the
/// convenio side of this rule doesn't need it (flat 15h/13h) — pass it to
/// get the amber/red split; omitting it keeps the old green/red behaviour.
RuleResult verifyA330PreIntercontinentalRest({
  required Duration plannedRest,
  bool precededByStandby = false,
  Duty? previousDuty,
}) {
  final minimumRest =
      precededByStandby ? const Duration(hours: 13) : const Duration(hours: 15);
  final suffix = precededByStandby ? ' (13h, preceded by standby)' : '';

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.13 (pre-intercontinental)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)}$suffix.',
    );
  }

  if (previousDuty != null) {
    const easaFloor = Duration(hours: 12);
    final easaMinimum = previousDuty.duration > easaFloor
        ? previousDuty.duration
        : easaFloor;
    const easaReference = 'EASA ORO.FTL.235 / CS FTL.1.235 (at home base): '
        'minimum rest = the preceding duty period or 12h, whichever is '
        'greater.';

    if (plannedRest >= easaMinimum) {
      return RuleResult(
        color: RuleColor.amber,
        clause: '3.13 (pre-intercontinental)',
        explanation: 'OWC (Outside Working Conditions). Planned rest of '
            '${_fmt(plannedRest)} does NOT meet the convenio minimum of '
            '${_fmt(minimumRest)}$suffix, but it DOES meet the EASA minimum '
            'of ${_fmt(easaMinimum)} — so it breaches the agreement but is '
            'legal. Requires Blue Sheet compensation / pilot consent.',
        easaReference: easaReference,
      );
    }

    return RuleResult(
      color: RuleColor.red,
      clause: '3.13 (pre-intercontinental)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} does NOT meet the '
          'required minimum of ${_fmt(minimumRest)}$suffix, and it also '
          'falls short of the EASA minimum of ${_fmt(easaMinimum)} — this '
          'is not just a breach of the agreement, it is illegal under '
          'EASA.',
      easaReference: easaReference,
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: '3.13 (pre-intercontinental)',
    explanation: 'Planned rest of ${_fmt(plannedRest)} does NOT meet the '
        'required minimum of ${_fmt(minimumRest)}$suffix.',
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

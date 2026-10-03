import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// A330 — Minimum rest following completion of a Standby duty (clause
/// 3.16.10 of the Widebody Consolidated Working Conditions 2025).
///
/// "A rest period of not less than thirteen hours shall follow the
/// completion of any standby duty." Unlike the A320/321's equivalent
/// (R-12, clause 3.17.5), the A330 text gives a single flat floor with no
/// "actual duty + 2h" formula — confirmed by reading 3.16 directly, this
/// is the only number given, regardless of whether a duty was actually
/// assigned during the standby or not.
///
/// EASA-equivalent floor (30/09): a standby duty under 2.21 is always a
/// Standby at Home (STBH) — the A330 agreement has no STBA-equivalent, only
/// STBH and STBB (a multi-day reserve block, not modelled by this rule).
/// So, like the A320/321's R-12, this is always at home base: EASA floor =
/// `max(duty assigned during standby, 12h)` — same pattern as R-06/R-11/R-12
/// and the A330 pre-intercontinental rule. [dutyAssignedOnStandby] is
/// optional because the agreement floor (13h) doesn't need it — pass it to
/// get the amber/red split; omitting it keeps the green/red-only behaviour.
RuleResult verifyA330AfterStandbyRest({
  required Duration plannedRest,
  Duty? dutyAssignedOnStandby,
}) {
  const minimumRest = Duration(hours: 13);

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.16.10',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)} (following completion of any '
          'standby duty).',
    );
  }

  if (dutyAssignedOnStandby != null) {
    const easaFloor = Duration(hours: 12);
    final easaMinimum = dutyAssignedOnStandby.duration > easaFloor
        ? dutyAssignedOnStandby.duration
        : easaFloor;
    const easaReference = 'EASA ORO.FTL.235 / CS FTL.1.235 (at home base): '
        'minimum rest = the preceding duty period or 12h, whichever is '
        'greater.';

    if (plannedRest >= easaMinimum) {
      return RuleResult(
        color: RuleColor.amber,
        clause: '3.16.10',
        explanation: 'OWC (Outside Working Conditions). Planned rest of '
            '${_fmt(plannedRest)} does NOT meet the agreement minimum of '
            '${_fmt(minimumRest)} (following completion of any standby '
            'duty), but it DOES meet the EASA minimum of '
            '${_fmt(easaMinimum)} — so it breaches the agreement but is '
            'legal. Requires Blue Sheet compensation / pilot consent.',
        easaReference: easaReference,
      );
    }

    return RuleResult(
      color: RuleColor.red,
      clause: '3.16.10',
      explanation: 'Planned rest of ${_fmt(plannedRest)} does NOT meet the '
          'required minimum of ${_fmt(minimumRest)} (following completion '
          'of any standby duty), and it also falls short of the EASA '
          'minimum of ${_fmt(easaMinimum)} — this is not just a breach of '
          'the agreement, it is illegal under EASA.',
      easaReference: easaReference,
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: '3.16.10',
    explanation: 'Planned rest of ${_fmt(plannedRest)} does NOT meet the '
        'required minimum of ${_fmt(minimumRest)} (following completion of '
        'any standby duty).',
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

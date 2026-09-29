import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// A330 — Minimum rest at an outstation following an eastbound
/// intercontinental duty (clause 3.13 of the Widebody Consolidated Working
/// Conditions 2025). Same formula as R-10 of the A320/321: duty real + time
/// difference, floor 14h.
///
/// No EASA amber zone (same conclusion as R-10 of the A320/321, see project
/// doc): this floor already matches EASA's own floor for rest away from
/// base after a significant time-zone difference, so the two coincide.
RuleResult verifyA330OutstationAfterEastboundRest({
  required Duty previousDuty,
  required Duration plannedRest,
}) {
  const absoluteMinimum = Duration(hours: 14);

  final formulaMinimum = previousDuty.duration + previousDuty.timeDifference;
  final minimumRest =
      formulaMinimum > absoluteMinimum ? formulaMinimum : absoluteMinimum;

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.13 (outstation after eastbound)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)}.',
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: '3.13 (outstation after eastbound)',
    explanation: 'Planned rest of ${_fmt(plannedRest)} does NOT meet the '
        'required minimum of ${_fmt(minimumRest)} — this floor already '
        'matches the EASA minimum for rest away from base after a '
        'significant time-zone difference, so this is also illegal under '
        'EASA, not just a breach of the agreement.',
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

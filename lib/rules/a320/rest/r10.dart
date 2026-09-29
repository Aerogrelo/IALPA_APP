import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// R-10 — Minimum rest at an Outstation following an eastbound transatlantic
/// duty (clause 3.14.2(e) of the A320/321 Working Conditions). The offset
/// added to the duty duration is the time difference of the previous duty,
/// not a fixed value.
///
/// No EASA amber zone here (checked 2026-09-28): this is rest taken away
/// from home base after a duty with a significant time-zone difference, and
/// EASA's own floor for that exact situation (ORO.FTL.235 / CS FTL.1.235)
/// is the preceding duty or 14h, whichever is greater — the same formula
/// the convenio already uses. The two floors coincide, so there is no gap
/// to open an amber (OWC) zone in: a breach of the convenio here is also a
/// breach of EASA, and stays red.
RuleResult verifyR10({
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
      clause: '3.14.2(e)',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)}.',
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: '3.14.2(e)',
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

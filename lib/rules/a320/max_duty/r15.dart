import '../../../models/duty.dart';
import '../../../models/rule_result.dart';
import 'effective_duty.dart';

/// R-15 — Maximum Flight Duty Time, Intercontinental (clause 3.11.2 of the
/// A320/321 Working Conditions).
///
/// Base maximum is 14h, reduced to 12h for Eastbound Transatlantic duties.
/// When the duty includes deadheading, the higher limits of clause
/// 2.11.4(a) apply instead: 16h general, 14h for Eastbound Transatlantic.
///
/// [stbhPortion]: the portion of a preceding Standby at Home that expired
/// before report, if any — only half of it counts, per 3.17.2(c) (see
/// [effectiveFlightDutyTime]).
///
/// [stbaPortion]: the portion of a preceding Standby at the Airport that
/// expired before report, if any — counts in full, per 2.16.1(b) (see
/// [effectiveFlightDutyTime]). A duty is normally preceded by at most one
/// of [stbhPortion] or [stbaPortion], never both.
///
/// [effectiveReportTime]: when the duty was delayed, the reference report
/// time from R-16 (clause 3.4.3) — used for the counted duty duration in
/// [effectiveFlightDutyTime]. When omitted, the duty's own report time is
/// used, i.e. no delay adjustment.
///
/// Commander's discretion (3.11.2, referenced via Appendix A / Flight
/// Operations Manual Part A, added 2026-09-28): same situation as R-14 —
/// the convenio gives no numeric limit of its own for this extension, so
/// the ceiling used here comes directly from EASA (ORO.FTL.205f): up to 2h
/// beyond the normal maximum, non-augmented crew, unforeseen circumstances
/// only. Does not verify against the (unavailable) Ops Manual Part A
/// limit, and does not separately track discretion hours already used via
/// R-16 delay relief.
///
/// On a green result, [RuleResult.marginToOwc] and
/// [RuleResult.marginToEasaLimit] are populated (added 29/09) so the UI
/// can show how much time is left before this duty would tip into OWC
/// (amber) or past the EASA discretion limit (red).
RuleResult verifyR15({
  required Duty duty,
  Duration stbhPortion = Duration.zero,
  Duration stbaPortion = Duration.zero,
  DateTime? effectiveReportTime,
}) {
  final isEastbound =
      duty.transatlanticDirection == TransatlanticDirection.eastbound;

  Duration maximum;
  String clause;
  String detail;

  if (duty.deadheading) {
    maximum =
        isEastbound ? const Duration(hours: 14) : const Duration(hours: 16);
    clause = '2.11.4(a)';
    detail = isEastbound
        ? 'deadheading, Eastbound Transatlantic'
        : 'deadheading, Intercontinental';
  } else {
    maximum =
        isEastbound ? const Duration(hours: 12) : const Duration(hours: 14);
    clause = isEastbound ? '3.11.2(c)' : '3.11.2(a)';
    detail = isEastbound ? 'Eastbound Transatlantic' : 'Intercontinental';
  }

  final effectiveDuty = effectiveFlightDutyTime(
    duty,
    stbhPortion: stbhPortion,
    stbaPortion: stbaPortion,
    effectiveReportTime: effectiveReportTime,
  );

  const discretionExtension = Duration(hours: 2);
  final discretionMaximum = maximum + discretionExtension;
  const easaReference = "EASA ORO.FTL.205(f): Commander's discretion may "
      'extend the maximum FDP by up to 2h for a non-augmented crew, only '
      'for unforeseen circumstances. The convenio defers to the Flight '
      'Operations Manual Part A for its own limit, which this app does '
      'not have access to.';

  if (effectiveDuty <= maximum) {
    return RuleResult(
      color: RuleColor.green,
      clause: clause,
      explanation: 'Flight duty time of ${_fmt(effectiveDuty)} is within '
          'the maximum of ${_fmt(maximum)} ($detail).',
      easaReference: easaReference,
      marginToOwc: maximum - effectiveDuty,
      marginToEasaLimit: discretionMaximum - effectiveDuty,
    );
  }

  if (effectiveDuty <= discretionMaximum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: clause,
      explanation: 'Flight duty time of ${_fmt(effectiveDuty)} EXCEEDS the '
          'normal maximum of ${_fmt(maximum)} ($detail), but is within the '
          "EASA Commander's discretion limit of ${_fmt(discretionMaximum)} "
          '(+2h, unforeseen circumstances only). This does not verify '
          'against the Ops Manual Part A limit.',
      easaReference: easaReference,
      owcOverage: effectiveDuty - maximum,
      marginToEasaLimit: discretionMaximum - effectiveDuty,
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: clause,
    explanation: 'Flight duty time of ${_fmt(effectiveDuty)} EXCEEDS even '
        "the EASA Commander's discretion limit of "
        '${_fmt(discretionMaximum)} ($detail).',
    easaReference: easaReference,
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

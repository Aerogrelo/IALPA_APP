import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// Minimum rest the day before an Intercontinental duty (clause 3.14.2(a)
/// of the A320/321 Working Conditions, cross-referenced with 2.10.6).
/// Identified 2026-09-28, was not in the original R-01/R-13 mapping.
///
/// The text does not give one combined formula, so the applicable minimum
/// is the GREATER of:
/// - the general rest rule (actual duty + 2h, min 12h — same formula as
///   R-06/R-11), and
/// - a special 15h floor, which only applies if the previous day's duty
///   exceeds 10 hours (2.10.6(b)/3.14.2(a)).
///
/// (Confirmed with Guillermo/IALPA 2026-09-28: there is no single clause
/// that combines "15h or duty+2" directly — both rules apply in parallel
/// and the stricter one governs.)
///
/// EASA-equivalent floor (added 2026-09-28, confirmed with Elena): since
/// intercontinental duties for this fleet always start FROM HOME BASE (the
/// pilots never operate an intercontinental duty away from base), the
/// applicable EASA rest rule is the general at-home-base one (ORO.FTL.235 /
/// CS FTL.1.235): minimum rest = the GREATER of the preceding duty period
/// or 12h — with no "+2h" component, unlike the convenio's own general
/// formula, so EASA's floor is more lenient than even the convenio's
/// general (non-intercontinental-specific) minimum.
///
/// If planned rest breaches the convenio minimum (15h floor / duty+2h) but
/// still meets this EASA floor, the result is AMBER: it is an Outside
/// Working Conditions (OWC) duty — it breaches the agreement but is legal
/// under EASA, and would require Blue Sheet compensation / pilot consent.
/// If it also breaches the EASA floor, the result is RED.
///
/// 2.10.6(a) (added 2026-09-30, confirmed with Elena): separately from the
/// rest-length checks above, the duty on the day BEFORE the intercontinental
/// must not commence before 06:00 LOCAL TIME at home base (Dublin). This is
/// a start-time rule, not a rest-length one, so it is checked against
/// [previousDayReportLocal] — a local-time value the pilot enters
/// separately from the UTC times used everywhere else in the app, since
/// [Duty] itself only ever stores UTC. There is no EASA-equivalent limit
/// for this specific clause, so on its own a breach never escalates a
/// result past AMBER (OWC) — but it never improves one either: if the
/// rest-length check already produced amber or red, that stands, and the
/// 06:00 breach is just noted as an additional reason.
/// [previousDayReportLocal] is optional: pass it whenever the local report
/// time is known (the new Minimum Rest screen always will) — when omitted,
/// this sub-check is simply skipped and the result reflects the
/// rest-length rules only.
RuleResult verifyMinRestBeforeIntercontinental({
  required Duty previousDayDuty,
  required Duration plannedRest,
  DateTime? previousDayReportLocal,
}) {
  const generalAbsoluteMinimum = Duration(hours: 12);
  const intercontinentalSpecialMinimum = Duration(hours: 15);
  const previousDayDutyThreshold = Duration(hours: 10);
  const earliestAllowedStart = Duration(hours: 6);

  final generalFormulaMinimum =
      previousDayDuty.duration + const Duration(hours: 2);
  var minimumRest = generalFormulaMinimum > generalAbsoluteMinimum
      ? generalFormulaMinimum
      : generalAbsoluteMinimum;

  final specialFloorApplies =
      previousDayDuty.duration > previousDayDutyThreshold;
  if (specialFloorApplies && intercontinentalSpecialMinimum > minimumRest) {
    minimumRest = intercontinentalSpecialMinimum;
  }

  final detail = specialFloorApplies
      ? 'previous day\'s duty (${_fmt(previousDayDuty.duration)}) exceeds '
          '10h, so the special 15h floor applies alongside the general '
          'rule (duty+2h, min 12h) — the greater governs'
      : 'previous day\'s duty (${_fmt(previousDayDuty.duration)}) does not '
          'exceed 10h, so only the general rule applies (duty+2h, min 12h)';

  // EASA floor: preceding duty period or 12h, whichever is greater (rest
  // is always at home base for this fleet's intercontinental duties).
  final easaMinimum = previousDayDuty.duration > generalAbsoluteMinimum
      ? previousDayDuty.duration
      : generalAbsoluteMinimum;
  const easaReference = 'EASA ORO.FTL.235 / CS FTL.1.235 (at home base): '
      'minimum rest = the preceding duty period or 12h, whichever is '
      'greater.';

  RuleColor color;
  String explanation;
  if (plannedRest >= minimumRest) {
    color = RuleColor.green;
    explanation = 'Planned rest of ${_fmt(plannedRest)} meets the required '
        'minimum of ${_fmt(minimumRest)} ($detail).';
  } else if (plannedRest >= easaMinimum) {
    color = RuleColor.amber;
    explanation = 'OWC (Outside Working Conditions). Planned rest of '
        '${_fmt(plannedRest)} does NOT meet the convenio minimum of '
        '${_fmt(minimumRest)} ($detail), but it DOES meet the EASA '
        'minimum of ${_fmt(easaMinimum)} — so it breaches the agreement '
        'but is legal. Requires Blue Sheet compensation / pilot consent.';
  } else {
    color = RuleColor.red;
    explanation = 'Planned rest of ${_fmt(plannedRest)} does NOT meet the '
        'required minimum of ${_fmt(minimumRest)} ($detail), and it also '
        'falls short of the EASA minimum of ${_fmt(easaMinimum)} — this is '
        'not just a breach of the agreement, it is illegal under EASA.';
  }

  // 2.10.6(a): the previous day's duty must not commence before 06:00 LT.
  if (previousDayReportLocal != null) {
    final startedAt = Duration(
      hours: previousDayReportLocal.hour,
      minutes: previousDayReportLocal.minute,
    );
    if (startedAt < earliestAllowedStart) {
      final note = 'Additionally, clause 2.10.6(a): the previous day\'s '
          'duty commenced at ${_hhmm(previousDayReportLocal)} LT, before '
          'the 06:00 LT floor for the day before an Intercontinental.';
      explanation = '$explanation $note';
      if (color == RuleColor.green) {
        color = RuleColor.amber;
      }
      // amber/red already stand — the note above still explains why.
    }
  }

  return RuleResult(
    color: color,
    clause: '2.10.6(a) / 3.14.2(a)',
    explanation: explanation,
    easaReference: easaReference,
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

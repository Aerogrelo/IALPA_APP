import '../../../models/rule_result.dart';

/// A330 — Change of Duty by the Airline, at Base, with at least fourteen
/// hours' notice (clause 3.2.5 of the Widebody Consolidated Working
/// Conditions 2025).
///
/// "At Base, when at least Fourteen (14) hours' notice is given, a pilot
/// rostered for a flight duty may be transferred to another duty of
/// similar duration whose reporting time is within plus or minus two (2)
/// hours of the original. Such notice shall be given not later than 2200
/// hours on the previous day. If the pilot consents the reporting time may
/// be brought forward by more than two (2) hours."
///
/// [similarDuration] captures the "duty of similar duration" condition,
/// which isn't something derivable from the two report times alone —
/// mirrors how other rules (e.g. [pre_intercontinental]'s
/// `precededByStandby`) take a qualitative flag as an input rather than
/// trying to infer it.
///
/// Colour: always amber on breach, never red — see
/// `verify_change_at_base_day_of_operation.dart` for why.
RuleResult verifyChangeAtBaseWithNotice({
  required DateTime originalReport,
  required DateTime newReport,
  required Duration noticeGiven,
  required bool similarDuration,
  bool noticeGivenBy2200PreviousDay = true,
  bool pilotConsents = false,
}) {
  const requiredNotice = Duration(hours: 14);
  const window = Duration(hours: 2);

  final laterLimitOk = !newReport.isAfter(originalReport.add(window));
  final earlierLimitOk = pilotConsents ||
      !newReport.isBefore(originalReport.subtract(window));

  final complies = noticeGiven >= requiredNotice &&
      noticeGivenBy2200PreviousDay &&
      similarDuration &&
      laterLimitOk &&
      earlierLimitOk;

  if (complies) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.5 (change of duty, at base, 14h notice)',
      explanation: 'Notice, timing and duty duration all meet the '
          'conditions for a change with 14h notice.',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.5 (change of duty, at base, 14h notice)',
    explanation: 'OWC (Outside Working Conditions). This change does not '
        'meet all the conditions of 3.2.5 (14h notice given by 2200 the '
        'previous day, duty of similar duration, reporting time within '
        '±2h of the original unless the pilot consents to an earlier '
        'time) — breaches the agreement, but this is a contractual limit '
        'only. Requires Blue Sheet compensation / pilot consent.',
  );
}

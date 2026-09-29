import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// R-17 — Standby at Home (STBH), maximum total elapsed time from the
/// start of the standby (clause 3.17.2(e) Continental / 3.17.2(f)
/// Intercontinental of the A320/321 Working Conditions).
///
/// This is an ADDITIONAL cap on top of R-14/R-15, not a replacement for
/// them: a duty can pass R-14/R-15 (which measure flight duty time,
/// counting the expired STBH portion at 50% via
/// [effectiveFlightDutyTime]) and still breach this one, because this
/// limit is measured differently — as the total elapsed time from the
/// moment the standby itself began, not from the flight duty's report
/// time.
///
/// Continental (3.17.2e):
/// - 16h if the flight duty falls entirely within 0630-0059.
/// - 13h if the flight duty enters the 0100-0629 window (at report or at
///   end, same band-membership style as R-14).
///
/// Intercontinental (3.17.2f):
/// - 14h, extendable by 1h for an [isExtendedDuty], but only if the pilot
///   has not operated an extended duty in the preceding 8 weeks
///   ([operatedExtendedDutyInPrior8Weeks]).
RuleResult verifyR17({
  required Duty duty,
  required DateTime standbyStart,
  required bool isIntercontinental,
  bool isExtendedDuty = false,
  bool operatedExtendedDutyInPrior8Weeks = false,
}) {
  final totalElapsed = duty.end.difference(standbyStart);

  Duration maximum;
  String clause;
  String detail;

  if (isIntercontinental) {
    maximum = const Duration(hours: 14);
    clause = '3.17.2(f)';
    detail = 'Intercontinental';

    if (isExtendedDuty && !operatedExtendedDutyInPrior8Weeks) {
      maximum = maximum + const Duration(hours: 1);
      detail = 'Intercontinental, extended duty (no extended duty in the '
          'preceding 8 weeks)';
    }
  } else {
    final reportMinutes = duty.report.hour * 60 + duty.report.minute;
    final endMinutes = duty.end.hour * 60 + duty.end.minute;

    const windowStart = 1 * 60; // 0100
    const windowEnd = 6 * 60 + 29; // 0629

    final entersNightWindow =
        (reportMinutes >= windowStart && reportMinutes <= windowEnd) ||
            (endMinutes >= windowStart && endMinutes <= windowEnd);

    clause = '3.17.2(e)';
    if (entersNightWindow) {
      maximum = const Duration(hours: 13);
      detail = 'enters the 0100-0629 window';
    } else {
      maximum = const Duration(hours: 16);
      detail = 'entirely within 0630-0059';
    }
  }

  if (totalElapsed <= maximum) {
    return RuleResult(
      color: RuleColor.green,
      clause: clause,
      explanation: 'Total elapsed time from the start of standby '
          '(${_fmt(totalElapsed)}) is within the maximum of '
          '${_fmt(maximum)} ($detail).',
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: clause,
    explanation: 'Total elapsed time from the start of standby '
        '(${_fmt(totalElapsed)}) EXCEEDS the maximum of ${_fmt(maximum)} '
        '($detail).',
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

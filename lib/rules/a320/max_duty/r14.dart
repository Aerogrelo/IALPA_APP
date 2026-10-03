import '../../../models/duty.dart';
import '../../../models/rule_result.dart';
import 'effective_duty.dart';

/// R-14 — Maximum Flight Duty Time, Continental (clause 3.11.1 of the
/// A320/321 Working Conditions).
///
/// The base maximum depends on the report/end time band:
/// - (a) report between 0100-0549, or end between 0200-0634 → 11h30
/// - (b) report between 0550-0619 → 12h
/// - (c) duty falling entirely between 0620-0159 → 13h
///
/// (d) The maximum in band (c) only is reduced by 30 minutes for each
/// sector from the 3rd sector onwards, up to a maximum reduction of 2h.
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
/// time from R-16 (clause 3.4.4) — used both for band selection here and
/// for the counted duty duration in [effectiveFlightDutyTime]. When
/// omitted, the duty's own report time is used, i.e. no delay adjustment.
///
/// Commander's discretion (3.11.1(e), added 2026-09-28): the agreement text
/// itself gives NO numeric limit for this extension — it only says "may be
/// extended by Commander's discretion as outlined in the Flight Operations
/// Manual Part A", a document not available to this app. So, unlike the
/// other amber rules, the applicable ceiling here is taken directly from
/// EASA (ORO.FTL.205(f)): up to 2h beyond the normal maximum, for a
/// non-augmented crew (always the case for this fleet), only for
/// unforeseen circumstances. This does NOT verify against the actual
/// Ops Manual Part A limit, which this app does not have access to. If the
/// duty exceeds the normal maximum but stays within this +2h EASA window,
/// the result is AMBER; beyond that, RED. Note: [effectiveDuty] does not
/// separately account for extension already used via R-16 delay relief
/// (which works by shifting the reference report time, not by directly
/// consuming discretion hours), so this is a simplification, not an exact
/// tracking of "hours of discretion already spent".
///
/// On a green result, [RuleResult.marginToOwc] and
/// [RuleResult.marginToEasaLimit] are populated (added 29/09) so the UI
/// can show how much time is left before this duty would tip into OWC
/// (amber) or past the EASA discretion limit (red).
RuleResult verifyR14({
  required Duty duty,
  Duration stbhPortion = Duration.zero,
  Duration stbaPortion = Duration.zero,
  DateTime? effectiveReportTime,
}) {
  final referenceReport = effectiveReportTime ?? duty.report;
  final reportMinutes = referenceReport.hour * 60 + referenceReport.minute;
  final endMinutes = duty.end.hour * 60 + duty.end.minute;

  const bandAReportStart = 1 * 60; // 0100
  const bandAReportEnd = 5 * 60 + 49; // 0549
  const bandAEndStart = 2 * 60; // 0200
  const bandAEndEnd = 6 * 60 + 34; // 0634
  const bandBStart = 5 * 60 + 50; // 0550
  const bandBEnd = 6 * 60 + 19; // 0619

  final inBandA = (reportMinutes >= bandAReportStart &&
          reportMinutes <= bandAReportEnd) ||
      (endMinutes >= bandAEndStart && endMinutes <= bandAEndEnd);
  final inBandB = reportMinutes >= bandBStart && reportMinutes <= bandBEnd;

  Duration baseMaximum;
  String clause;
  String bandDetail;

  if (inBandA) {
    baseMaximum = const Duration(hours: 11, minutes: 30);
    clause = '3.11.1(a)';
    bandDetail = 'report between 0100-0549 or end between 0200-0634';
  } else if (inBandB) {
    baseMaximum = const Duration(hours: 12);
    clause = '3.11.1(b)';
    bandDetail = 'report between 0550-0619';
  } else {
    baseMaximum = const Duration(hours: 13);
    clause = '3.11.1(c)';
    bandDetail = 'duty entirely within 0620-0159';
  }

  var maximum = baseMaximum;
  var sectorDetail = '';
  if (clause == '3.11.1(c)' && duty.sectors >= 3) {
    final extraSectors = duty.sectors - 2; // sectors from the 3rd onward
    final reductionMinutes = (extraSectors * 30).clamp(0, 120);
    maximum = maximum - Duration(minutes: reductionMinutes);
    sectorDetail =
        ', reduced by ${reductionMinutes}min for ${duty.sectors} sectors '
        '(3.11.1d)';
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
      'for unforeseen circumstances. The agreement (3.11.1e) defers to the '
      'Flight Operations Manual Part A for its own limit, which this app '
      'does not have access to.';

  if (effectiveDuty <= maximum) {
    return RuleResult(
      color: RuleColor.green,
      clause: clause,
      explanation: 'Flight duty time of ${_fmt(effectiveDuty)} is within '
          'the maximum of ${_fmt(maximum)} ($bandDetail$sectorDetail).',
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
          'normal maximum of ${_fmt(maximum)} ($bandDetail$sectorDetail), '
          "but is within the EASA Commander's discretion limit of "
          '${_fmt(discretionMaximum)} (+2h, unforeseen circumstances only). '
          'This does not verify against the Ops Manual Part A limit.',
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
        '${_fmt(discretionMaximum)} ($bandDetail$sectorDetail).',
    easaReference: easaReference,
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

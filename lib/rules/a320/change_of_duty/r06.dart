import '../../../models/rule_result.dart';

/// R-06 — Change of Duty, Intercontinental, with ≥14h notice, at Base
/// (clause 3.2.4(c) of the A320/321 Working Conditions).
///
/// At Base, when at least fourteen (14) hours notice is given (not later
/// than 2200 the previous day — simplified here to just checking the
/// notice duration), a pilot rostered for a flight duty may be
/// transferred to another duty of similar duration whose report time is
/// within plus or minus two (+/-2) hours of the original.
///
/// If the pilot consents, the report time may be brought forward by MORE
/// than 2h, entitled to a Blue Sheet payment for an agreed OWC duty —
/// mirrors the A330's equivalent rule (3.2.5): [pilotConsents] removes
/// the earlier-side limit only, the later-side +2h limit still applies.
///
/// [similarDuration] is not independently verified here (the source text
/// does not define "similar" numerically) — flagged the same way as its
/// A330 equivalent.
///
/// A breach of this clause can never be red on its own — EASA does not
/// regulate scheduling flexibility (same reasoning as R-01 through R-05).
RuleResult verifyR06({
  required DateTime originalReport,
  required DateTime newReport,
  required Duration noticeGiven,
  bool pilotConsents = false,
}) {
  const requiredNotice = Duration(hours: 14);

  if (noticeGiven < requiredNotice) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.2.4(c)',
      explanation: 'Only ${_fmt(noticeGiven)} notice was given; this '
          'clause requires at least 14h notice.',
    );
  }

  final latest = originalReport.add(const Duration(hours: 2));
  final earliest = pilotConsents
      ? null
      : originalReport.subtract(const Duration(hours: 2));

  final withinLater = !newReport.isAfter(latest);
  final withinEarlier = earliest == null || !newReport.isBefore(earliest);

  if (withinLater && withinEarlier) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.4(c)',
      explanation: pilotConsents
          ? 'New report is within 2h later of the original (earlier '
              'side unrestricted with pilot consent), with '
              '${_fmt(noticeGiven)} notice.'
          : 'New report is within ±2h of the original, with '
              '${_fmt(noticeGiven)} notice.',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.4(c)',
    explanation: 'New report is outside the allowed window '
        '(${pilotConsents ? "up to 2h later" : "±2h"}), even with '
        '${_fmt(noticeGiven)} notice. Breaches the agreement, not EASA.',
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

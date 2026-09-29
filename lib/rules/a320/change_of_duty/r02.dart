import '../../../models/rule_result.dart';

/// R-02 — Change of Duty, Continental, with ≥24h notice, at Base
/// (clause 3.2.3(b) of the A320/321 Working Conditions).
///
/// When a minimum of 24 hours notice is given, a pilot's duty may be
/// changed to another provided the new duty reports within 2h of the
/// original (earlier or later).
///
/// The source text reads "...reports not more than 2 hours earlier or
/// finishes more than 2 hours later" — missing a "not" before "more than
/// 2 hours later", which would otherwise allow an unbounded delay. Elena
/// confirmed (29/09) this is a printing error and the window should be
/// symmetric ±2h, consistent with the equivalent Intercontinental clause
/// (3.2.4(c)) and the A330's clause 3.2.5. If IALPA's actual practice
/// differs, this is a one-line fix.
///
/// A breach of this clause can never be red on its own — EASA does not
/// regulate scheduling flexibility (same reasoning as R-01).
RuleResult verifyR02({
  required DateTime originalReport,
  required DateTime newReport,
  required Duration noticeGiven,
}) {
  const requiredNotice = Duration(hours: 24);

  if (noticeGiven < requiredNotice) {
    return RuleResult(
      color: RuleColor.amber,
      clause: '3.2.3(b)',
      explanation: 'Only ${_fmt(noticeGiven)} notice was given; this '
          'clause requires at least 24h notice to use the ±2h window.',
    );
  }

  final earliest = originalReport.subtract(const Duration(hours: 2));
  final latest = originalReport.add(const Duration(hours: 2));

  if (!newReport.isBefore(earliest) && !newReport.isAfter(latest)) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.3(b)',
      explanation: 'New report is within 2h of the original, with '
          '${_fmt(noticeGiven)} notice (≥24h required).',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.3(b)',
    explanation: 'New report is more than 2h from the original, even '
        'with ${_fmt(noticeGiven)} notice. Breaches the agreement, not '
        'EASA.',
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

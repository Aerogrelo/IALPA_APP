import '../../../models/rule_result.dart';

/// R-04 — Standby Duties Commencing Before 0800, Brought Forward
/// (clause 3.2.3(f) of the A320/321 Working Conditions).
///
/// A standby duty commencing before 0800 may only be brought forward
/// (moved earlier) with prior notice, and only up to a maximum:
/// - up to 1h earlier, with a minimum of 12h notice
/// - up to 2h earlier, with a minimum of 24h notice
///
/// A pilot may accept larger changes for OWC Blue Sheet payment (0.19%),
/// which this rule does not model — it only checks the baseline limits.
/// Only applies when the original standby starts before 0800; a duty not
/// being brought forward at all (same time or later) always complies.
///
/// A breach of this clause can never be red on its own — EASA does not
/// regulate scheduling flexibility (same reasoning as R-01/R-02/R-03).
RuleResult verifyR04({
  required DateTime originalStandbyStart,
  required DateTime newStandbyStart,
  required Duration noticeGiven,
}) {
  final startsBefore0800 = originalStandbyStart.hour < 8;
  final broughtForwardBy =
      originalStandbyStart.difference(newStandbyStart);

  if (!startsBefore0800 || broughtForwardBy <= Duration.zero) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.3(f)',
      explanation: !startsBefore0800
          ? 'Original standby does not start before 0800; this clause '
              'does not apply.'
          : 'The new standby start is not earlier than the original.',
    );
  }

  final within1hWith12h = broughtForwardBy <= const Duration(hours: 1) &&
      noticeGiven >= const Duration(hours: 12);
  final within2hWith24h = broughtForwardBy <= const Duration(hours: 2) &&
      noticeGiven >= const Duration(hours: 24);

  if (within1hWith12h || within2hWith24h) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.2.3(f)',
      explanation: 'Standby brought forward by ${_fmt(broughtForwardBy)} '
          'with ${_fmt(noticeGiven)} notice, within the allowed limits.',
    );
  }

  return RuleResult(
    color: RuleColor.amber,
    clause: '3.2.3(f)',
    explanation: 'Standby brought forward by ${_fmt(broughtForwardBy)} '
        'with only ${_fmt(noticeGiven)} notice, exceeding the allowed '
        'limits (1h with 12h notice, or 2h with 24h notice). Breaches '
        'the agreement, not EASA.',
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

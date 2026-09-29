import '../../../models/rule_result.dart';

/// R-13 — Unscheduled Overnights (clause 3.14.4 of the A320/321 Working
/// Conditions).
///
/// This clause does not set its own minimum rest figure. It modifies the
/// minimum rest that already applies under the relevant base rule
/// (3.14.1/3.14.2/3.14.3, depending on duty type) in two ways:
/// - The rest period is counted from the moment the decision to overnight
///   was taken, not from the actual end of the duty (this is handled
///   upstream, when [plannedRest] is computed — it must already be measured
///   from that decision moment, not from the duty's scheduled end).
/// - The minimum required may be reduced by 1 hour if a meal was provided
///   "on the ground" within the 3 hours prior to that decision.
///
/// [baseMinimumRest] is the minimum that would apply under whichever base
/// rule matches the duty type (e.g. the result of [verifyR06] or
/// [verifyMinRestBeforeIntercontinental]'s own minimum calculation).
RuleResult verifyR13({
  required Duration baseMinimumRest,
  required bool mealProvidedOnGround,
  required Duration plannedRest,
}) {
  final reduction =
      mealProvidedOnGround ? const Duration(hours: 1) : Duration.zero;
  final minimumRest = baseMinimumRest - reduction;

  final detail = mealProvidedOnGround
      ? 'a meal was provided on the ground within 3h of the decision to '
          'overnight, reducing the base minimum of '
          '${_fmt(baseMinimumRest)} by 1h'
      : 'no qualifying meal was provided, so the base minimum of '
          '${_fmt(baseMinimumRest)} applies unchanged';

  if (plannedRest >= minimumRest) {
    return RuleResult(
      color: RuleColor.green,
      clause: '3.14.4',
      explanation: 'Planned rest of ${_fmt(plannedRest)} meets the required '
          'minimum of ${_fmt(minimumRest)} ($detail).',
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: '3.14.4',
    explanation: 'Planned rest of ${_fmt(plannedRest)} does NOT meet the '
        'required minimum of ${_fmt(minimumRest)} ($detail).',
  );
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

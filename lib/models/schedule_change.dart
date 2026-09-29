import 'duty.dart';

/// A company-proposed change to a pilot's roster: the original duty vs the
/// proposed duty, plus the context needed to check it against the IALPA
/// agreement (surrounding duties, whether it creates an unscheduled
/// overnight, etc).
class ScheduleChange {
  final DateTime notifiedAt;
  final Duty original;
  final Duty proposed;
  final Duty? previousDuty;
  final Duty? nextDuty;
  final bool unscheduledOvernight;
  final bool mealProvidedOnGround;
  final bool pilotConsents;

  const ScheduleChange({
    required this.notifiedAt,
    required this.original,
    required this.proposed,
    this.previousDuty,
    this.nextDuty,
    this.unscheduledOvernight = false,
    this.mealProvidedOnGround = false,
    this.pilotConsents = false,
  });

  Duration get noticePeriod => original.report.difference(notifiedAt);
  Duration get reportTimeDifference =>
      proposed.report.difference(original.report);
  Duration get endTimeDifference => proposed.end.difference(original.end);
}

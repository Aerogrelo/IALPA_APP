import '../../../models/duty.dart';
import '../../../models/rule_result.dart';

/// A330 — Maximum Flight Duty Time.
///
/// REWRITTEN 29/09 after reading the source PDF directly (previously this
/// was an inferred guess, flagged as an assumption pending IALPA — see the
/// project doc). The real structure has two layers:
///
/// **Planning limitations (Section 2 — the normal, non-delayed limit):**
/// - 2.15.1: normal FDP, two-pilot operation: **12h**.
/// - 2.15.2: Eastbound Transatlantic / through-the-night North/South FDP,
///   two-pilot operation: **11h**.
/// - 2.15.3: normal FDP, augmented crew: **15h** outside the WOCL (02:00-
///   05:59). Reduced by the duty's encroachment into the WOCL, up to a
///   maximum reduction of 2h: 100% of the encroachment if the duty
///   *starts* in the WOCL, 50% if it only ends in or fully encompasses the
///   WOCL. (South Africa is an explicit exception to this limit, not
///   modelled here — flag if that ever becomes relevant.)
/// - 2.15.4: augmented crew, aircraft without an agreed cockpit rest area:
///   **14h westbound / 13h eastbound**.
/// - 2.15.5: heavy crew: **17h** flat.
///
/// **Operating limitations (Section 3, clause 3.10 — "in the event of
/// delays" only):**
/// - 3.10.1: the two-pilot limits (2.15.1/2.15.2) may be extended by
///   **+1h**, capped at a maximum of **16h** — except should the duty (as
///   operating pilot) enter the period 01:00-06:29, in which case the
///   limit is a flat **12h** regardless of the +1h extension.
/// - 3.10.2: the augmented-crew limit may be extended by **+2h**, or only
///   **+1h** if that extension would itself encroach the WOCL by at least
///   that much.
/// - 3.10.3: without an agreed cockpit rest area, the operating limit is
///   **15h westbound / 14h eastbound** — exactly 2.15.4 + 1h, following
///   the same delay-extension pattern as 3.10.1 (not a Planning-vs-
///   Operating inconsistency like questions 5/6 for the A320/321).
///
/// [delayed] selects which layer applies: false → the Planning limit
/// (2.15.x) as-is; true → the Operating limit (3.10.x), i.e. the
/// delay-extended version. This app is mainly used to check a schedule
/// *change*, so [delayed] should usually be true when checking the
/// consequence of an actual delay, and false when checking a roster as
/// originally planned.
///
/// Heavy crew (2.15.5) has no referenced extension in 3.10, so [delayed]
/// has no effect for [A330CrewType.heavy] — flagged as an open question if
/// it turns out heavy crew delays are ever relevant in practice.
///
/// **EASA amber layer (added 29/09):** beyond the applicable convenio
/// maximum computed above (whichever layer/branch applies), EASA's
/// commander's discretion (ORO.FTL.205(f)) allows extending the FDP by up
/// to a further **2h**, for unforeseen circumstances only — same pattern
/// and same reference already used for the A320/321's R-14/R-15. Applied
/// here uniformly across all three crew types as a simplification: EASA's
/// real discretion limits can differ by crew complement, and the actual
/// Ops Manual Part A criteria are not available to this app. Beyond the
/// convenio maximum but within the +2h discretion window → amber; beyond
/// that → red.
enum A330CrewType { twoPilot, augmented, heavy }

RuleResult verifyA330MaxDuty({
  required Duty duty,
  A330CrewType crewType = A330CrewType.twoPilot,
  bool delayed = false,
  bool agreedCockpitRestArea = true,
  TransatlanticDirection? direction,
  bool throughTheNight = false,
  Duration woclEncroachment = Duration.zero,
  bool dutyStartsInWocl = false,
  bool extensionInvadesWocl = false,
}) {
  Duration maximum;
  String clause;
  String detail;

  if (crewType == A330CrewType.heavy) {
    maximum = const Duration(hours: 17);
    clause = '2.15.5 (heavy crew)';
    detail = 'heavy crew';
  } else if (crewType == A330CrewType.augmented) {
    if (!agreedCockpitRestArea) {
      final planningMax = direction == TransatlanticDirection.westbound
          ? const Duration(hours: 14)
          : const Duration(hours: 13);
      if (delayed) {
        maximum = direction == TransatlanticDirection.westbound
            ? const Duration(hours: 15)
            : const Duration(hours: 14);
        clause = '3.10.3 (no agreed cockpit rest area, delayed)';
      } else {
        maximum = planningMax;
        clause = '2.15.4 (no agreed cockpit rest area)';
      }
      detail = direction == TransatlanticDirection.westbound
          ? 'augmented crew, westbound, no agreed cockpit rest area'
          : 'augmented crew, eastbound, no agreed cockpit rest area';
    } else {
      const woclLimit = Duration(hours: 2);
      final cappedEncroachment =
          woclEncroachment > woclLimit ? woclLimit : woclEncroachment;
      final reduction = cappedEncroachment == Duration.zero
          ? Duration.zero
          : (dutyStartsInWocl
              ? cappedEncroachment
              : cappedEncroachment * 0.5);
      final planningMax = const Duration(hours: 15) - reduction;

      if (delayed) {
        final extension = extensionInvadesWocl
            ? const Duration(hours: 1)
            : const Duration(hours: 2);
        maximum = planningMax + extension;
        clause = '3.10.2 (augmented crew, delayed)';
      } else {
        maximum = planningMax;
        clause = '2.15.3 (augmented crew)';
      }
      detail = 'augmented crew'
          '${reduction > Duration.zero ? ', WOCL-reduced by ${_fmt(reduction)}' : ''}';
    }
  } else {
    final isReducedCase = throughTheNight ||
        direction == TransatlanticDirection.eastbound;
    final baseline =
        isReducedCase ? const Duration(hours: 11) : const Duration(hours: 12);
    final baseClause = isReducedCase ? '2.15.2' : '2.15.1';

    if (delayed) {
      final entersNightWindow = _entersNightWindow(duty);
      if (entersNightWindow) {
        maximum = const Duration(hours: 12);
      } else {
        final extended = baseline + const Duration(hours: 1);
        const cap = Duration(hours: 16);
        maximum = extended > cap ? cap : extended;
      }
      clause = '3.10.1 (two-pilot, delayed)';
    } else {
      maximum = baseline;
      clause = baseClause;
    }
    detail = isReducedCase
        ? 'two-pilot, eastbound TA / through-the-night'
        : 'two-pilot, normal';
  }

  const discretionExtension = Duration(hours: 2);
  final discretionMaximum = maximum + discretionExtension;
  const easaReference = "EASA ORO.FTL.205(f): Commander's discretion may "
      'extend the maximum FDP by up to 2h, only for unforeseen '
      'circumstances. Applied uniformly across crew types here as a '
      'simplification (the Ops Manual Part A, which may set different or '
      'additional criteria, is not available to this app).';

  if (duty.duration <= maximum) {
    return RuleResult(
      color: RuleColor.green,
      clause: clause,
      explanation: 'Flight duty time of ${_fmt(duty.duration)} is within '
          'the maximum of ${_fmt(maximum)} ($detail).',
      easaReference: easaReference,
      marginToOwc: maximum - duty.duration,
      marginToEasaLimit: discretionMaximum - duty.duration,
    );
  }

  if (duty.duration <= discretionMaximum) {
    return RuleResult(
      color: RuleColor.amber,
      clause: clause,
      explanation: 'Flight duty time of ${_fmt(duty.duration)} EXCEEDS the '
          'normal maximum of ${_fmt(maximum)} ($detail), but is within '
          "the EASA Commander's discretion limit of "
          '${_fmt(discretionMaximum)} (+2h, unforeseen circumstances '
          'only). This does not verify against the Ops Manual Part A '
          'limit.',
      easaReference: easaReference,
      owcOverage: duty.duration - maximum,
      marginToEasaLimit: discretionMaximum - duty.duration,
    );
  }

  return RuleResult(
    color: RuleColor.red,
    clause: clause,
    explanation: 'Flight duty time of ${_fmt(duty.duration)} EXCEEDS even '
        "the EASA Commander's discretion limit of "
        '${_fmt(discretionMaximum)} ($detail).',
    easaReference: easaReference,
  );
}

bool _entersNightWindow(Duty duty) {
  // Checks whether [duty.report, duty.end) overlaps the 0100-0629 window on
  // any day the duty spans, by testing that window on the report day, the
  // day before, and the day after (enough for any realistic duty length).
  bool overlaps(DateTime windowStart) {
    final windowEnd = windowStart.add(const Duration(hours: 5, minutes: 29));
    return duty.report.isBefore(windowEnd) && duty.end.isAfter(windowStart);
  }

  final reportDay =
      DateTime(duty.report.year, duty.report.month, duty.report.day, 1, 0);
  return overlaps(reportDay.subtract(const Duration(days: 1))) ||
      overlaps(reportDay) ||
      overlaps(reportDay.add(const Duration(days: 1)));
}

String _fmt(Duration d) {
  final hours = d.inMinutes ~/ 60;
  final minutes = d.inMinutes % 60;
  return '${hours}h${minutes.toString().padLeft(2, '0')}';
}

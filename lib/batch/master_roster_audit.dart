/// Batch audit engine for a full Master Roster (every pilot, every day in
/// one published roster PDF — IALPA's own legality check of the roster
/// AS PUBLISHED, confirmed 01/10 with Elena: this is NOT a before/after
/// change-detector, which is why it only runs Maximum Duty + Minimum
/// Rest, never Change of Duty (that needs two roster snapshots to
/// compare, which a single Master Roster never gives).
///
/// Reuses, unchanged, the exact rule functions and Minimum-Rest scenario
/// detection already written and tested for the single-duty manual
/// screens (`scenario_detection.dart` is a verbatim port of the private
/// detection methods in `min_rest_input_screen.dart`) — this file is only
/// the walk-every-pilot/every-day orchestration on top of that, not a
/// second rule engine.
///
/// Known, documented gaps (never silently guessed around — surfaced as
/// `Finding.missingFields` / `Finding.notApplicable` instead):
/// - A330 crew type (two-pilot/augmented/heavy) is never printed in the
///   Master Roster (confirmed 01/10 against a real 330 CP roster) — every
///   INTERCONTINENTAL A330 day is flagged `missingFields: ['crewType']`
///   rather than assumed. Continental A330 days default to two-pilot
///   (same default the manual screen itself uses), since Aer Lingus's
///   augmented/heavy A330 crews are only ever used on the long
///   Intercontinental sectors in practice.
/// - Deadheading, delayed-duty, WOCL encroachment and agreed-cockpit-rest
///   -area are not printed either. These default the same way the manual
///   screen already defaults them when left blank (documented there as a
///   known undercount for some edge cases) — unlike crew type, there is
///   no code in the Master Roster that could tell us otherwise, so this
///   matches existing precedent rather than inventing a new assumption.
/// - "Preceded by standby" (STBH/STBA before a flight duty) is only
///   detected for Minimum Rest (via `day.standbys`), not fed into Maximum
///   Duty's `stbhPortion`/`stbaPortion` — the Master Roster doesn't
///   distinguish "flew after a standby" from "always scheduled to fly"
///   for the SAME day, so this is left at zero (no credit), same as the
///   manual screen's "None" default.
/// - The `preIntercontinental` Minimum Rest scenario (clause 2.10.6a — the
///   day BEFORE an Intercontinental) is not auto-detected here, same as
///   the manual screen itself (see `scenario_detection.dart`) — it needs
///   the day-before-the-day-before, which the per-day hints don't carry.
library master_roster_audit;

import '../models/duty.dart';
import '../models/roster_day.dart';
import '../models/rule_result.dart';
import '../rules/a320/max_duty/r14.dart';
import '../rules/a320/max_duty/r15.dart';
import '../rules/a320/rest/min_rest_before_intercontinental.dart';
import '../rules/a320/rest/r06.dart';
import '../rules/a320/rest/r07.dart';
import '../rules/a320/rest/r08.dart';
import '../rules/a320/rest/r09.dart';
import '../rules/a320/rest/r10.dart';
import '../rules/a320/rest/r11.dart';
import '../rules/a320/rest/r12.dart';
import '../rules/a330/max_duty/verify_max_duty.dart';
import '../rules/a330/rest/after_standby.dart';
import '../rules/a330/rest/base_continental.dart';
import '../rules/a330/rest/outstation_after_eastbound.dart';
import '../rules/a330/rest/outstation_continental.dart';
import '../rules/a330/rest/post_intercontinental_westbound.dart';
import '../rules/a330/rest/pre_intercontinental.dart';
import '../rules/a330/rest/through_the_night.dart';
import 'scenario_detection.dart';

/// 01/10 (Full Roster Audit): the individual-roster parser's
/// `stitch_overnight_duties` (`roster_service/roster_parser.py`) fills
/// BOTH printed rows of a duty that spans a midnight row-break — day N
/// gets a copied finish time (from day N+1's arrival leg), and day N+1
/// gets a copied REPORT time (day N's original report) — so a pilot
/// picking either day in the manual single-day picker sees the same
/// complete duty either way. That's the right design there, but this
/// batch screen audits every day independently: without recognising this
/// flag, day N+1 reads as a brand-new duty running from the (copied,
/// hours-earlier) report to day N+1's own finish — producing impossible
/// durations and negative "rest" before it. Found live (01/10) from the
/// actual durations Elena saw on screen (24h, 53h, a -11h52 "rest").
/// A day carrying this flag is the tail end of the duty already counted
/// (and verified) on the day before it, not a new one — the Master
/// Roster's own classifier never produces this flag (it drops the
/// leading bare time instead of copying a report forward, see
/// `classify_master_roster_days.py`), so this only ever matters for the
/// individual-roster "Full Roster Audit" screen.
const _reportCopiedFromPreviousDay = 'report_time_from_previous_day';

enum AuditFleet { a320, a330 }

enum FindingKind { maxDuty, minRest }

/// One line of the audit report: either a computed [result], or a reason
/// nothing was computed (`missingFields` — the Master Roster doesn't say,
/// ask the pilot/crewing; `notApplicable` — nothing to check that day/gap).
/// Exactly one of [result] / [missingFields] / [notApplicable] is set.
class Finding {
  Finding({
    required this.pilotName,
    required this.pilotId,
    required this.date,
    required this.kind,
    this.result,
    this.missingFields = const [],
    this.notApplicable,
    this.relatedDate,
  });

  final String pilotName;
  final String? pilotId;
  final String date; // the Master Roster's own column label, e.g. 'Oct28'
  final FindingKind kind;
  final RuleResult? result;
  final List<String> missingFields;
  final String? notApplicable;

  /// When set, the data actually missing belongs to a DIFFERENT day than
  /// [date] — e.g. a Minimum Rest finding dated the day a pilot reports
  /// back for duty, whose rest couldn't be checked because the day
  /// BEFORE it has an unresolved finish time. [inputDate] is what the
  /// review screen should group and ask for a fix against.
  final String? relatedDate;

  String get inputDate => relatedDate ?? date;

  bool get needsInput => missingFields.isNotEmpty;
  bool get skipped => notApplicable != null;

  @override
  String toString() {
    if (result != null) return '[$pilotName $date ${kind.name}] $result';
    if (needsInput) {
      return '[$pilotName $date ${kind.name}] needs input: '
          '${missingFields.join(", ")}';
    }
    return '[$pilotName $date ${kind.name}] not applicable: $notApplicable';
  }
}

/// A single pilot's parsed Master Roster record — [days] keyed by the
/// roster's own date columns ('Oct28'...), in the SAME order the PDF
/// printed them (chronological), which the walk below relies on.
class PilotRecord {
  PilotRecord({
    required this.name,
    required this.id,
    required this.days,
  });

  factory PilotRecord.fromJson(Map<String, dynamic> json) {
    final daysJson = (json['days'] as Map<String, dynamic>);
    final days = <String, RosterDay>{};
    daysJson.forEach((date, dayJson) {
      days[date] = RosterDay.fromJson(dayJson as Map<String, dynamic>);
    });
    final id = json['id'] as String?;
    // A handful of Master Roster rows (name split across lines, OCR/parse
    // edge case in the PDF) come through with no name. Rather than crash
    // the whole batch over a few rows, fall back to the pilot ID (or a
    // placeholder) so that pilot still shows up in the report, clearly
    // labelled, instead of silently vanishing.
    final name = json['name'] as String? ??
        (id != null ? 'PILOTO SIN NOMBRE (id $id)' : 'PILOTO SIN NOMBRE (fila sin identificar)');
    return PilotRecord(
      name: name,
      id: id,
      days: days,
    );
  }

  final String name;
  final String? id;
  final Map<String, RosterDay> days;
}

/// Number of real flight legs that day (excludes standby/ground-duty
/// entries, which carry no `flightNumber`) — used as Max Duty's
/// `sectors`, which only counts flown sectors.
int _sectorCount(RosterDay day) =>
    day.legs.where((l) => l['flightNumber'] != null).length;

bool _hasRealFlight(RosterDay day) => _sectorCount(day) > 0;

List<Finding> auditPilotMaxDuty(
  PilotRecord pilot,
  AuditFleet fleet, {
  Map<String, A330CrewType> crewTypeOverrides = const {},
}) {
  final findings = <Finding>[];
  pilot.days.forEach((date, day) {
    if (day.flags.contains(_reportCopiedFromPreviousDay)) {
      // The whole duty was already counted (and verified) on the day
      // before — see the flag's doc comment above.
      findings.add(Finding(
        pilotName: pilot.name, pilotId: pilot.id, date: date,
        kind: FindingKind.maxDuty,
        notApplicable: 'this is the tail end of a duty already checked '
            'on the day before',
      ));
      return;
    }
    if (day.status != 'ok' || day.kind != null) {
      if (day.status == 'needs_review') {
        findings.add(Finding(
          pilotName: pilot.name,
          pilotId: pilot.id,
          date: date,
          kind: FindingKind.maxDuty,
          missingFields: _missingFieldsFromDay(day, fleet),
        ));
      }
      return;
    }
    if (!_hasRealFlight(day)) return; // standby/ground-only day: N/A
    if (day.reportTimeUtc == null || day.trailingTimeUtc == null) return;

    final duty = Duty(
      report: day.reportTimeUtc!,
      end: day.trailingTimeUtc!,
      type: DutyType.flight,
      sectors: _sectorCount(day),
      transatlanticDirection: day.transatlanticDirection == 'eastbound'
          ? TransatlanticDirection.eastbound
          : day.transatlanticDirection == 'westbound'
              ? TransatlanticDirection.westbound
              : TransatlanticDirection.none,
    );

    if (fleet == AuditFleet.a320) {
      final result = day.intercontinental ? verifyR15(duty: duty) : verifyR14(duty: duty);
      findings.add(Finding(
        pilotName: pilot.name, pilotId: pilot.id, date: date,
        kind: FindingKind.maxDuty, result: result,
      ));
    } else {
      if (day.intercontinental) {
        // Confirmed 01/10: crew type is never printed. Never assumed —
        // unless the review screen has supplied one for this exact day
        // (crewTypeOverrides), in which case use that instead of
        // flagging it again.
        final override = crewTypeOverrides[date];
        if (override == null) {
          findings.add(Finding(
            pilotName: pilot.name, pilotId: pilot.id, date: date,
            kind: FindingKind.maxDuty, missingFields: const ['crewType'],
          ));
          return;
        }
        final result = verifyA330MaxDuty(duty: duty, crewType: override);
        findings.add(Finding(
          pilotName: pilot.name, pilotId: pilot.id, date: date,
          kind: FindingKind.maxDuty, result: result,
        ));
        return;
      }
      final result = verifyA330MaxDuty(duty: duty); // defaults: two-pilot
      findings.add(Finding(
        pilotName: pilot.name, pilotId: pilot.id, date: date,
        kind: FindingKind.maxDuty, result: result,
      ));
    }
  });
  return findings;
}

List<String> _missingFieldsFromDay(RosterDay day, AuditFleet fleet) {
  // RosterDay.fromJson doesn't carry the pipeline's own `missingFields`
  // field (not part of the app's existing model) — re-derive the same
  // verdict from what IS on the model: no trailing time -> finishTime;
  // Intercontinental A330 -> crewType too (01/10 fix: this used to only
  // ever flag finishTime here, so a transatlantic day with BOTH gaps
  // made the reviewer fill the finish time, submit, and only THEN get
  // asked for crew type in a second round — asking for both up front
  // instead).
  //
  // Crew type is an A330-only concept (two-pilot/augmented/heavy —
  // A330CrewType). The A320/321 DOES fly Intercontinental too (confirmed
  // 01/10 with Elena — some A321s cross the Atlantic, same as the A330),
  // but its Maximum Duty rules (R14/R15) don't take a crew-type
  // parameter at all, so never ask for one on that fleet.
  final fields = <String>[];
  if (day.reportTimeUtc != null && day.trailingTimeUtc == null) {
    fields.add('finishTime');
  }
  if (day.intercontinental && fleet == AuditFleet.a330) {
    fields.add('crewType');
  }
  if (fields.isEmpty) fields.add('unresolved');
  return fields;
}

List<Finding> auditPilotMinRest(PilotRecord pilot, AuditFleet fleet) {
  final findings = <Finding>[];
  RosterDay? previousDuty;
  String? previousDate;
  // Most recent FLOWN day whose own data was incomplete (needs_review,
  // or report known but no finish time) — the rest ENDING on the next
  // real duty day can't be checked until this is resolved. Tracked
  // separately from previousDuty/previousDate so that gap can be
  // surfaced as a needsInput Finding on the next duty day, instead of
  // just silently producing no Finding at all (01/10 fix — the earlier
  // version dropped these checks with no trace, which the review screen
  // would then never show as something to fix).
  String? unresolvedDutyDate;

  for (final date in pilot.days.keys) {
    final day = pilot.days[date]!;

    if (day.flags.contains(_reportCopiedFromPreviousDay)) {
      // Not a new duty starting after a rest — it's the tail end of the
      // one already checked on the day before (see the flag's doc
      // comment above), so there's no "rest ending here" to verify. Its
      // OWN finish time (if this day has further activity after landing)
      // is still real, though, and still marks where that whole duty
      // actually ends for whatever rest check comes after it.
      if (day.trailingTimeUtc != null) {
        previousDuty = day;
        previousDate = date;
        unresolvedDutyDate = null;
      }
      continue;
    }

    if (day.status == 'needs_review') {
      findings.add(Finding(
        pilotName: pilot.name, pilotId: pilot.id, date: date,
        kind: FindingKind.minRest, missingFields: _missingFieldsFromDay(day, fleet),
      ));
      unresolvedDutyDate = date;
      previousDuty = null;
      previousDate = null;
      continue;
    }
    if (day.status != 'ok') {
      // e.g. 'empty' — nothing to say either way.
      previousDuty = null;
      previousDate = null;
      continue;
    }
    if (day.kind != null) continue; // day off: doesn't break or extend
    if (day.reportTimeUtc == null) continue; // pure ground/ambiguous day

    if (previousDuty != null && previousDuty.trailingTimeUtc != null) {
      final plannedRest =
          day.reportTimeUtc!.difference(previousDuty.trailingTimeUtc!);
      final finding = _checkMinRest(
        pilot, previousDate!, date, previousDuty, plannedRest, fleet,
      );
      if (finding != null) findings.add(finding);
    } else if (unresolvedDutyDate != null) {
      // This day's incoming rest can't be verified: it follows a duty
      // whose own finish time is unknown. Say so, pointing at the day
      // that actually needs the missing data (relatedDate), not this
      // one — this one is fine, it's the day BEFORE it that's the gap.
      findings.add(Finding(
        pilotName: pilot.name, pilotId: pilot.id, date: date,
        kind: FindingKind.minRest,
        missingFields: const ['finishTime'],
        relatedDate: unresolvedDutyDate,
      ));
    }

    if (day.trailingTimeUtc != null) {
      previousDuty = day;
      previousDate = date;
      unresolvedDutyDate = null;
    } else {
      // Report known, finish not (overnight-continuation gap) — can't
      // anchor the NEXT rest period either until that's resolved.
      previousDuty = null;
      previousDate = null;
      unresolvedDutyDate = date;
    }
  }
  return findings;
}

Finding? _checkMinRest(
  PilotRecord pilot,
  String previousDate,
  String date,
  RosterDay previousDuty,
  Duration plannedRest,
  AuditFleet fleet,
) {
  final duty = Duty(
    report: previousDuty.reportTimeUtc!,
    end: previousDuty.trailingTimeUtc!,
    type: DutyType.flight,
    timeDifference: Duration(
      hours: previousDuty.intercontinentalTimeDifferenceHours ?? 0,
    ),
  );

  if (fleet == AuditFleet.a320) {
    final scenario = detectA320Scenario(previousDuty);
    if (scenario == null) {
      return Finding(
        pilotName: pilot.name, pilotId: pilot.id, date: date,
        kind: FindingKind.minRest,
        notApplicable: "couldn't determine the rest situation for "
            '$previousDate (base/outstation/Intercontinental unresolved)',
      );
    }
    RuleResult result;
    switch (scenario) {
      case A320RestScenario.base:
        result = verifyR06(previousDuty: duty, plannedRest: plannedRest);
        break;
      case A320RestScenario.outstation:
        result = verifyR07(previousDuty: duty, plannedRest: plannedRest);
        break;
      case A320RestScenario.throughTheNight:
        result = verifyR08(previousDuty: duty, plannedRest: plannedRest);
        break;
      case A320RestScenario.postWestboundTransatlantic:
        result = verifyR09(previousDuty: duty, plannedRest: plannedRest);
        break;
      case A320RestScenario.outstationAfterEastboundTransatlantic:
        result = verifyR10(previousDuty: duty, plannedRest: plannedRest);
        break;
      case A320RestScenario.postIntercontinentalSameDay:
        result = verifyR11(previousDuty: duty, plannedRest: plannedRest);
        break;
      case A320RestScenario.afterStandby:
        // Never known from the Master Roster whether a duty was actually
        // assigned during the standby (see file-level doc) -> assumed
        // not assigned, same as the manual screen's default.
        result = verifyR12(dutyAssignedOnStandby: null, plannedRest: plannedRest);
        break;
      case A320RestScenario.preIntercontinental:
        result = verifyMinRestBeforeIntercontinental(
          previousDayDuty: duty, plannedRest: plannedRest,
        );
        break;
    }
    return Finding(
      pilotName: pilot.name, pilotId: pilot.id, date: date,
      kind: FindingKind.minRest, result: result,
    );
  }

  final scenario = detectA330Scenario(previousDuty);
  if (scenario == null) {
    return Finding(
      pilotName: pilot.name, pilotId: pilot.id, date: date,
      kind: FindingKind.minRest,
      notApplicable: "couldn't determine the rest situation for "
          '$previousDate (base/outstation/Intercontinental unresolved, or '
          'a same-day Intercontinental round trip, which has no dedicated '
          'A330 rest scenario)',
    );
  }
  RuleResult result;
  switch (scenario) {
    case A330RestScenario.baseContinental:
      result = verifyA330BaseContinentalRest(previousDuty: duty, plannedRest: plannedRest);
      break;
    case A330RestScenario.outstationContinental:
      result = verifyA330OutstationContinentalRest(previousDuty: duty, plannedRest: plannedRest);
      break;
    case A330RestScenario.throughTheNight:
      result = verifyA330ThroughTheNightRest(previousDuty: duty, plannedRest: plannedRest);
      break;
    case A330RestScenario.postIntercontinentalWestbound:
      result = verifyA330PostIntercontinentalWestboundRest(previousDuty: duty, plannedRest: plannedRest);
      break;
    case A330RestScenario.outstationAfterEastbound:
      result = verifyA330OutstationAfterEastboundRest(previousDuty: duty, plannedRest: plannedRest);
      break;
    case A330RestScenario.preIntercontinental:
      result = verifyA330PreIntercontinentalRest(plannedRest: plannedRest, previousDuty: duty);
      break;
    case A330RestScenario.afterStandby:
      result = verifyA330AfterStandbyRest(plannedRest: plannedRest);
      break;
  }
  return Finding(
    pilotName: pilot.name, pilotId: pilot.id, date: date,
    kind: FindingKind.minRest, result: result,
  );
}

class AuditSummary {
  AuditSummary(this.findings);
  final List<Finding> findings;

  int get red => findings.where((f) => f.result?.color == RuleColor.red).length;
  int get amber => findings.where((f) => f.result?.color == RuleColor.amber).length;
  int get green => findings.where((f) => f.result?.color == RuleColor.green).length;
  int get needsInput => findings.where((f) => f.needsInput).length;
  int get skipped => findings.where((f) => f.skipped).length;

  List<Finding> get breaches =>
      findings.where((f) => f.result?.color == RuleColor.red || f.result?.color == RuleColor.amber).toList();
}

AuditSummary auditMasterRoster(List<PilotRecord> pilots, AuditFleet fleet) {
  final all = <Finding>[];
  for (final pilot in pilots) {
    all.addAll(auditPilotMaxDuty(pilot, fleet));
    all.addAll(auditPilotMinRest(pilot, fleet));
  }
  return AuditSummary(all);
}

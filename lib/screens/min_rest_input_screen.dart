import 'package:flutter/material.dart';

import '../models/duty.dart';
import '../models/roster_day.dart';
import '../models/rule_result.dart';
import '../rules/a320/rest/min_rest_before_intercontinental.dart';
import '../rules/a320/rest/r06.dart';
import '../rules/a320/rest/r07.dart';
import '../rules/a320/rest/r08.dart';
import '../rules/a320/rest/r09.dart';
import '../rules/a320/rest/r10.dart';
import '../rules/a320/rest/r11.dart';
import '../rules/a320/rest/r12.dart';
import '../rules/a330/rest/base_continental.dart';
import '../rules/a330/rest/outstation_after_eastbound.dart';
import '../rules/a330/rest/outstation_continental.dart';
import '../rules/a330/rest/post_intercontinental_westbound.dart';
import '../rules/a330/rest/pre_intercontinental.dart';
import '../rules/a330/rest/through_the_night.dart';
import 'fleet_selection_screen.dart';
import 'result_screen.dart';
import 'widgets/date_time_field.dart';
import 'widgets/roster_import_button.dart';

/// A320/321 clause group 3.14 (plus 3.17.5 for the post-standby case) —
/// one rule per rest situation (R-06 through R-12).
///
/// **R-13 (Unscheduled Overnights, 3.14.4) is deliberately NOT on this
/// screen** — flagged to Elena 2026-09-30. Unlike the others, it doesn't
/// set its own minimum: it MODIFIES whichever base rule above already
/// applies (reduces it by 1h if a qualifying meal was provided on the
/// ground), so it needs a "which base rule, plus this adjustment" shape
/// this screen doesn't have yet. Coming in a follow-up.
enum _A320RestScenario {
  base, // R-06, 3.14.1(a)
  outstation, // R-07, 3.14.1(b)
  throughTheNight, // R-08, 3.14.1(c)
  postWestboundTransatlantic, // R-09, 3.14.2(b)
  outstationAfterEastboundTransatlantic, // R-10, 3.14.2(e)
  postIntercontinentalSameDay, // R-11, 3.14.3(b)
  afterStandby, // R-12, 3.17.5
  preIntercontinental, // 2.10.6(a)/3.14.2(a)
}

/// The A330's clause 3.13 covers the same six situations minus the two
/// A320/321-only ones (R-12's standby case and R-13's overnight-meal
/// adjustment have no A330 equivalent).
enum _A330RestScenario {
  baseContinental,
  outstationContinental,
  throughTheNight,
  postIntercontinentalWestbound,
  outstationAfterEastbound,
  preIntercontinental,
}

const Map<_A320RestScenario, String> _a320ScenarioLabels = {
  _A320RestScenario.base: 'At base, after Continental/Canary Is. (3.14.1a)',
  _A320RestScenario.outstation: 'At an outstation (3.14.1b)',
  _A320RestScenario.throughTheNight:
      'After a through-the-night duty (3.14.1c)',
  _A320RestScenario.postWestboundTransatlantic:
      'After a westbound Transatlantic (3.14.2b)',
  _A320RestScenario.outstationAfterEastboundTransatlantic:
      'At an outstation, after eastbound Transatlantic (3.14.2e)',
  _A320RestScenario.postIntercontinentalSameDay:
      'After an Intercontinental returning same day (3.14.3b)',
  _A320RestScenario.afterStandby: 'After completing a Standby (3.17.5)',
  _A320RestScenario.preIntercontinental:
      'Day before an Intercontinental (2.10.6a / 3.14.2a)',
};

const Map<_A330RestScenario, String> _a330ScenarioLabels = {
  _A330RestScenario.baseContinental: 'At base, after a Continental duty (3.13)',
  _A330RestScenario.outstationContinental:
      'At an outstation, Continental (3.13)',
  _A330RestScenario.throughTheNight:
      'After a through-the-night duty (3.13)',
  _A330RestScenario.postIntercontinentalWestbound:
      'After a westbound Intercontinental (3.13.2)',
  _A330RestScenario.outstationAfterEastbound:
      'At an outstation, after an eastbound Intercontinental (3.13)',
  _A330RestScenario.preIntercontinental: 'Before an Intercontinental (3.13)',
};

/// Fourth screen (for Minimum Rest, Group B): enter the previous duty
/// (or standby) and the start of the next one, and check the rest taken
/// in between against clause 3.14 (A320/321) / 3.13 (A330), plus 2.10.6(a)
/// for the day before an intercontinental.
///
/// Same shape as [ChangeOfDutyInputScreen]: a scenario selector leads,
/// then only the fields that scenario's rule actually needs are shown.
/// Unlike Change of Duty, these rules CAN resolve to red — a rest breach
/// can be a genuine EASA/safety issue, not just a contractual one.
///
/// 30/09 (later the same day, Elena's request): importing a day from the
/// roster now also tries to AUTO-DETECT which situation applies — base
/// vs. outstation, Continental vs. Intercontinental, direction — using
/// the station and Intercontinental hints the roster service now sends
/// per day (see [RosterDay]). The detected situation is only ever a
/// pre-selected suggestion shown in a banner: the radio list right below
/// it is unchanged and always overridable, because this screen checks
/// legal/contractual compliance and should never be a silent black box.
/// Detection deliberately does NOT cover "day before an Intercontinental"
/// (2.10.6a) or "Intercontinental returning same day" (R-11) — both need
/// to look at a *different* day's duty than the one being imported, which
/// this screen doesn't fetch yet; those stay manual-only for now.
class MinRestInputScreen extends StatefulWidget {
  const MinRestInputScreen({super.key, required this.fleet});

  final Fleet fleet;

  @override
  State<MinRestInputScreen> createState() => _MinRestInputScreenState();
}

class _MinRestInputScreenState extends State<MinRestInputScreen> {
  _A320RestScenario _a320Scenario = _A320RestScenario.base;
  _A330RestScenario _a330Scenario = _A330RestScenario.baseContinental;

  // Previous duty (or standby): report is only used to compute its
  // duration, end doubles as "when rest starts" unless overridden below.
  DateTime _previousReport =
      DateTime.now().toUtc().subtract(const Duration(hours: 10));
  DateTime _previousEnd = DateTime.now().toUtc();

  // Start of the next duty — rest is measured from [_previousEnd] to here.
  DateTime _newReport = DateTime.now().toUtc().add(const Duration(hours: 12));

  int _timeDifferenceHours = 0;

  // R-12 (A320/321 only): whether a duty was actually assigned during the
  // standby, per clause 3.17.5.
  bool _dutyAssignedDuringStandby = false;

  // Pre-intercontinental, both fleets.
  bool _precededByStandby = false; // A330 only (flat 13h vs 15h)

  // 2.10.6(a), A320/321 pre-intercontinental only: the previous day's duty
  // must not commence before 06:00 LOCAL TIME at home base (Dublin) — a
  // wall-clock check, unrelated to the UTC times used everywhere else on
  // this screen. Reuses [DateTimeField] purely to collect the digits (the
  // "UTC" it stores them under has no meaning here beyond "don't apply
  // device-local-time conversion" — see that widget's own doc comment).
  DateTime _previousDayReportLocal =
      DateTime.now().toUtc().subtract(const Duration(hours: 28));

  // Set after a roster import, explaining what (if anything) was
  // auto-detected — shown as a banner above the situation picker.
  String? _detectionNote;

  @override
  Widget build(BuildContext context) {
    final fleetLabel = widget.fleet == Fleet.a320 ? 'A320/321' : 'A330';

    return Scaffold(
      appBar: AppBar(title: Text('Minimum Rest — $fleetLabel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Fills the previous duty's report/end from the roster instead
          // of typing it in, and — when the imported day gives enough
          // information — pre-selects the matching situation below.
          RosterImportButton(
            onImported: (report, finish) => setState(() {
              _previousReport = report;
              _previousEnd = finish;
            }),
            onImportedDay: _onRosterDayImported,
          ),
          if (_detectionNote != null) ...[
            const SizedBox(height: 12),
            _buildDetectionBanner(),
          ],
          const SizedBox(height: 16),
          if (widget.fleet == Fleet.a320) ..._buildA320Form(),
          if (widget.fleet == Fleet.a330) ..._buildA330Form(),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _verify,
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _detectionNote!,
              style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Auto-detection from an imported roster day (30/09)
  // ---------------------------------------------------------------------

  void _onRosterDayImported(RosterDay day) {
    if (widget.fleet == Fleet.a320) {
      final detected = _detectA320Scenario(day);
      setState(() {
        if (detected != null) _a320Scenario = detected;
        if (day.intercontinentalTimeDifferenceHours != null) {
          _timeDifferenceHours = day.intercontinentalTimeDifferenceHours!;
        }
        if (detected == _A320RestScenario.afterStandby) {
          _dutyAssignedDuringStandby = day.legs.isNotEmpty;
        }
        _detectionNote = _noteFor(
          detected == null ? null : _a320ScenarioLabels[detected],
        );
      });
    } else {
      final detected = _detectA330Scenario(day);
      setState(() {
        if (detected != null) _a330Scenario = detected;
        if (day.intercontinentalTimeDifferenceHours != null) {
          _timeDifferenceHours = day.intercontinentalTimeDifferenceHours!;
        }
        _detectionNote = _noteFor(
          detected == null ? null : _a330ScenarioLabels[detected],
        );
      });
    }
  }

  String _noteFor(String? detectedLabel) {
    if (detectedLabel == null) {
      return 'Couldn\'t auto-detect the situation for this day from the '
          'roster — please pick it manually below.';
    }
    return 'Detected from the roster: $detectedLabel. Check it matches, or '
        'pick a different situation below if not.';
  }

  /// Best-guess situation for the A320/321 from a roster day's station and
  /// Intercontinental hints. Returns null when it can't be determined
  /// confidently — the pilot picks manually in that case, same as before
  /// roster import existed.
  _A320RestScenario? _detectA320Scenario(RosterDay day) {
    // Without any classified leg or standby for this day, the station and
    // Intercontinental hints are unreliable (they only get populated by
    // walking actual legs/standbys) — better to say nothing than guess
    // from stale station-tracking state carried over from an earlier day.
    if (day.legs.isEmpty && day.standbys.isEmpty) return null;
    if (day.standbys.isNotEmpty) return _A320RestScenario.afterStandby;
    if (day.intercontinental) {
      // R-09 vs R-10 are distinguished by WHERE the rest is taken (at
      // base vs at an outstation), not by the physical compass direction
      // of the specific leg that day — "Westbound"/"Eastbound" in the
      // clause names the whole pairing, not this leg. A same-day round
      // trip (out and back to base in one day) is neither: it's R-11,
      // with its own lower minimum, and misreading it as R-09 would
      // quietly apply the wrong (higher) floor.
      final sameDayReturn = day.legs.length >= 2 &&
          day.reportStation == 'DUB' &&
          day.finishStation == 'DUB';
      if (sameDayReturn) {
        return _A320RestScenario.postIntercontinentalSameDay;
      }
      if (day.finishStation == 'DUB') {
        return _A320RestScenario.postWestboundTransatlantic;
      }
      if (day.finishStation != null) {
        return _A320RestScenario.outstationAfterEastboundTransatlantic;
      }
      return null;
    }
    if (_isThroughTheNight(day) && day.finishStation == 'DUB') {
      return _A320RestScenario.throughTheNight;
    }
    if (day.finishStation == 'DUB') return _A320RestScenario.base;
    if (day.finishStation != null) return _A320RestScenario.outstation;
    return null;
  }

  _A330RestScenario? _detectA330Scenario(RosterDay day) {
    if (day.legs.isEmpty) return null;
    if (day.intercontinental) {
      // Same reasoning as the A320/321 above: base vs outstation decides
      // R-09/R-10-equivalent, not the leg's physical direction. A
      // same-day round trip has no dedicated A330 scenario on this
      // screen, so it's left for the pilot to pick manually rather than
      // guessed at.
      final sameDayReturn = day.legs.length >= 2 &&
          day.reportStation == 'DUB' &&
          day.finishStation == 'DUB';
      if (sameDayReturn) return null;
      if (day.finishStation == 'DUB') {
        return _A330RestScenario.postIntercontinentalWestbound;
      }
      if (day.finishStation != null) {
        return _A330RestScenario.outstationAfterEastbound;
      }
      return null;
    }
    if (_isThroughTheNight(day) && day.finishStation == 'DUB') {
      return _A330RestScenario.throughTheNight;
    }
    if (day.finishStation == 'DUB') return _A330RestScenario.baseContinental;
    if (day.finishStation != null) {
      return _A330RestScenario.outstationContinental;
    }
    return null;
  }

  bool _isThroughTheNight(RosterDay day) {
    final suggestion = day.suggestedTimes();
    if (suggestion == null) return false;
    final probe = Duty(
      report: suggestion.report,
      end: suggestion.finish,
      type: DutyType.flight,
    );
    return probe.isThroughTheNight;
  }

  // ---------------------------------------------------------------------
  // A320/321
  // ---------------------------------------------------------------------

  List<Widget> _buildA320Form() {
    return [
      const Text('Situation', style: TextStyle(fontWeight: FontWeight.bold)),
      RadioListTile<_A320RestScenario>(
        title: Text(_a320ScenarioLabels[_A320RestScenario.base]!),
        value: _A320RestScenario.base,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: Text(_a320ScenarioLabels[_A320RestScenario.outstation]!),
        value: _A320RestScenario.outstation,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: Text(_a320ScenarioLabels[_A320RestScenario.throughTheNight]!),
        value: _A320RestScenario.throughTheNight,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: Text(
            _a320ScenarioLabels[_A320RestScenario.postWestboundTransatlantic]!),
        value: _A320RestScenario.postWestboundTransatlantic,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: Text(_a320ScenarioLabels[
            _A320RestScenario.outstationAfterEastboundTransatlantic]!),
        value: _A320RestScenario.outstationAfterEastboundTransatlantic,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: Text(
            _a320ScenarioLabels[_A320RestScenario.postIntercontinentalSameDay]!),
        value: _A320RestScenario.postIntercontinentalSameDay,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: Text(_a320ScenarioLabels[_A320RestScenario.afterStandby]!),
        value: _A320RestScenario.afterStandby,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title:
            Text(_a320ScenarioLabels[_A320RestScenario.preIntercontinental]!),
        value: _A320RestScenario.preIntercontinental,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      const SizedBox(height: 16),
      ..._buildA320Fields(),
      const SizedBox(height: 8),
      const Text(
        'Note: Unscheduled Overnights (3.14.4) isn\'t on this screen yet — '
        'it modifies another rule\'s minimum rather than being a '
        'standalone check. Coming in a future update.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
    ];
  }

  List<Widget> _buildA320Fields() {
    final needsTimeDifference = _a320Scenario ==
            _A320RestScenario.postWestboundTransatlantic ||
        _a320Scenario == _A320RestScenario.outstationAfterEastboundTransatlantic;

    if (_a320Scenario == _A320RestScenario.afterStandby) {
      return [
        SwitchListTile(
          title: const Text('A duty was assigned during the standby'),
          value: _dutyAssignedDuringStandby,
          onChanged: (v) => setState(() => _dutyAssignedDuringStandby = v),
        ),
        if (_dutyAssignedDuringStandby) ...[
          DateTimeField(
            label: 'Duty report time (UTC)',
            value: _previousReport,
            onChanged: (v) => setState(() => _previousReport = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'Duty end time (UTC)',
            value: _previousEnd,
            onChanged: (v) => setState(() => _previousEnd = v),
          ),
        ] else
          DateTimeField(
            label: 'Standby end time (UTC)',
            value: _previousEnd,
            onChanged: (v) => setState(() => _previousEnd = v),
          ),
        const SizedBox(height: 12),
        _buildNewReportField(),
      ];
    }

    return [
      DateTimeField(
        label: 'Previous duty report time (UTC)',
        value: _previousReport,
        onChanged: (v) => setState(() => _previousReport = v),
      ),
      const SizedBox(height: 12),
      DateTimeField(
        label: 'Previous duty end time (UTC)',
        value: _previousEnd,
        onChanged: (v) => setState(() => _previousEnd = v),
      ),
      const SizedBox(height: 12),
      _buildNewReportField(),
      if (needsTimeDifference) ...[
        const SizedBox(height: 8),
        _buildTimeDifferenceStepper(),
      ],
      if (_a320Scenario == _A320RestScenario.preIntercontinental) ...[
        const SizedBox(height: 12),
        DateTimeField(
          label: 'Previous day duty report time (LOCAL, Dublin)',
          value: _previousDayReportLocal,
          onChanged: (v) => setState(() => _previousDayReportLocal = v),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Clause 2.10.6(a): this is the report time of the duty on the '
            'day BEFORE the intercontinental, in Dublin local time — not '
            'UTC like the other fields on this screen.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    ];
  }

  RuleResult _verifyA320() {
    final previousDuty = Duty(
      report: _previousReport,
      end: _previousEnd,
      type: DutyType.flight,
      timeDifference: Duration(hours: _timeDifferenceHours),
    );

    switch (_a320Scenario) {
      case _A320RestScenario.base:
        return verifyR06(previousDuty: previousDuty, plannedRest: _plannedRest);
      case _A320RestScenario.outstation:
        return verifyR07(previousDuty: previousDuty, plannedRest: _plannedRest);
      case _A320RestScenario.throughTheNight:
        return verifyR08(previousDuty: previousDuty, plannedRest: _plannedRest);
      case _A320RestScenario.postWestboundTransatlantic:
        return verifyR09(previousDuty: previousDuty, plannedRest: _plannedRest);
      case _A320RestScenario.outstationAfterEastboundTransatlantic:
        return verifyR10(previousDuty: previousDuty, plannedRest: _plannedRest);
      case _A320RestScenario.postIntercontinentalSameDay:
        return verifyR11(previousDuty: previousDuty, plannedRest: _plannedRest);
      case _A320RestScenario.afterStandby:
        return verifyR12(
          dutyAssignedOnStandby:
              _dutyAssignedDuringStandby ? previousDuty : null,
          plannedRest: _plannedRest,
        );
      case _A320RestScenario.preIntercontinental:
        return verifyMinRestBeforeIntercontinental(
          previousDayDuty: previousDuty,
          plannedRest: _plannedRest,
          previousDayReportLocal: _previousDayReportLocal,
        );
    }
  }

  // ---------------------------------------------------------------------
  // A330
  // ---------------------------------------------------------------------

  List<Widget> _buildA330Form() {
    return [
      const Text('Situation', style: TextStyle(fontWeight: FontWeight.bold)),
      RadioListTile<_A330RestScenario>(
        title: Text(_a330ScenarioLabels[_A330RestScenario.baseContinental]!),
        value: _A330RestScenario.baseContinental,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title:
            Text(_a330ScenarioLabels[_A330RestScenario.outstationContinental]!),
        value: _A330RestScenario.outstationContinental,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title: Text(_a330ScenarioLabels[_A330RestScenario.throughTheNight]!),
        value: _A330RestScenario.throughTheNight,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title: Text(_a330ScenarioLabels[
            _A330RestScenario.postIntercontinentalWestbound]!),
        value: _A330RestScenario.postIntercontinentalWestbound,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title: Text(
            _a330ScenarioLabels[_A330RestScenario.outstationAfterEastbound]!),
        value: _A330RestScenario.outstationAfterEastbound,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title:
            Text(_a330ScenarioLabels[_A330RestScenario.preIntercontinental]!),
        value: _A330RestScenario.preIntercontinental,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      const SizedBox(height: 16),
      ..._buildA330Fields(),
    ];
  }

  List<Widget> _buildA330Fields() {
    final needsTimeDifference = _a330Scenario ==
            _A330RestScenario.postIntercontinentalWestbound ||
        _a330Scenario == _A330RestScenario.outstationAfterEastbound;

    return [
      DateTimeField(
        label: 'Previous duty report time (UTC)',
        value: _previousReport,
        onChanged: (v) => setState(() => _previousReport = v),
      ),
      const SizedBox(height: 12),
      DateTimeField(
        label: 'Previous duty end time (UTC)',
        value: _previousEnd,
        onChanged: (v) => setState(() => _previousEnd = v),
      ),
      const SizedBox(height: 12),
      _buildNewReportField(),
      if (needsTimeDifference) ...[
        const SizedBox(height: 8),
        _buildTimeDifferenceStepper(),
      ],
      if (_a330Scenario == _A330RestScenario.preIntercontinental)
        SwitchListTile(
          title: const Text('Rest is preceded by a standby duty (13h '
              'floor instead of 15h)'),
          value: _precededByStandby,
          onChanged: (v) => setState(() => _precededByStandby = v),
        ),
    ];
  }

  RuleResult _verifyA330() {
    final previousDuty = Duty(
      report: _previousReport,
      end: _previousEnd,
      type: DutyType.flight,
      timeDifference: Duration(hours: _timeDifferenceHours),
    );

    switch (_a330Scenario) {
      case _A330RestScenario.baseContinental:
        return verifyA330BaseContinentalRest(
          previousDuty: previousDuty,
          plannedRest: _plannedRest,
        );
      case _A330RestScenario.outstationContinental:
        return verifyA330OutstationContinentalRest(
          previousDuty: previousDuty,
          plannedRest: _plannedRest,
        );
      case _A330RestScenario.throughTheNight:
        return verifyA330ThroughTheNightRest(
          previousDuty: previousDuty,
          plannedRest: _plannedRest,
        );
      case _A330RestScenario.postIntercontinentalWestbound:
        return verifyA330PostIntercontinentalWestboundRest(
          previousDuty: previousDuty,
          plannedRest: _plannedRest,
        );
      case _A330RestScenario.outstationAfterEastbound:
        return verifyA330OutstationAfterEastboundRest(
          previousDuty: previousDuty,
          plannedRest: _plannedRest,
        );
      case _A330RestScenario.preIntercontinental:
        return verifyA330PreIntercontinentalRest(
          plannedRest: _plannedRest,
          precededByStandby: _precededByStandby,
          previousDuty: previousDuty,
        );
    }
  }

  // ---------------------------------------------------------------------
  // Shared
  // ---------------------------------------------------------------------

  Widget _buildNewReportField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DateTimeField(
          label: 'New duty report time (UTC) — end of rest',
          value: _newReport,
          onChanged: (v) => setState(() => _newReport = v),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Planned rest: ${_fmtDuration(_plannedRest)}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeDifferenceStepper() {
    return Row(
      children: [
        const Text('Time difference of the previous duty: '),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: _timeDifferenceHours > 0
              ? () => setState(() => _timeDifferenceHours--)
              : null,
        ),
        Text('${_timeDifferenceHours}h'),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => setState(() => _timeDifferenceHours++),
        ),
      ],
    );
  }

  /// Rest is measured from the previous duty's (or standby's) end to the
  /// next duty's report, never negative.
  Duration get _plannedRest {
    final diff = _newReport.difference(_previousEnd);
    return diff.isNegative ? Duration.zero : diff;
  }

  String _fmtDuration(Duration d) {
    final hours = d.inMinutes ~/ 60;
    final minutes = d.inMinutes % 60;
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }

  void _verify() {
    final result =
        widget.fleet == Fleet.a320 ? _verifyA320() : _verifyA330();

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    );
  }
}

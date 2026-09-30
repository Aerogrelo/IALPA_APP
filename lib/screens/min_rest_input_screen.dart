import 'package:flutter/material.dart';

import '../models/duty.dart';
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

/// Fourth screen (for Minimum Rest, Group B): enter the previous duty
/// (or standby) and the start of the next one, and check the rest taken
/// in between against clause 3.14 (A320/321) / 3.13 (A330), plus 2.10.6(a)
/// for the day before an intercontinental.
///
/// Same shape as [ChangeOfDutyInputScreen]: a scenario selector leads,
/// then only the fields that scenario's rule actually needs are shown.
/// Unlike Change of Duty, these rules CAN resolve to red — a rest breach
/// can be a genuine EASA/safety issue, not just a contractual one.
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

  @override
  Widget build(BuildContext context) {
    final fleetLabel = widget.fleet == Fleet.a320 ? 'A320/321' : 'A330';

    return Scaffold(
      appBar: AppBar(title: Text('Minimum Rest — $fleetLabel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Fills the previous duty's report/end from the roster instead
          // of typing it in — same service used on the other two screens.
          RosterImportButton(
            onImported: (report, finish) => setState(() {
              _previousReport = report;
              _previousEnd = finish;
            }),
          ),
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

  // ---------------------------------------------------------------------
  // A320/321
  // ---------------------------------------------------------------------

  List<Widget> _buildA320Form() {
    return [
      const Text('Situation', style: TextStyle(fontWeight: FontWeight.bold)),
      RadioListTile<_A320RestScenario>(
        title: const Text('At base, after Continental/Canary Is. (3.14.1a)'),
        value: _A320RestScenario.base,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: const Text('At an outstation (3.14.1b)'),
        value: _A320RestScenario.outstation,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: const Text('After a through-the-night duty (3.14.1c)'),
        value: _A320RestScenario.throughTheNight,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: const Text('After a westbound Transatlantic (3.14.2b)'),
        value: _A320RestScenario.postWestboundTransatlantic,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: const Text(
            'At an outstation, after eastbound Transatlantic (3.14.2e)'),
        value: _A320RestScenario.outstationAfterEastboundTransatlantic,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: const Text(
            'After an Intercontinental returning same day (3.14.3b)'),
        value: _A320RestScenario.postIntercontinentalSameDay,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: const Text('After completing a Standby (3.17.5)'),
        value: _A320RestScenario.afterStandby,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320RestScenario>(
        title: const Text(
            'Day before an Intercontinental (2.10.6a / 3.14.2a)'),
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
        title: const Text('At base, after a Continental duty (3.13)'),
        value: _A330RestScenario.baseContinental,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title: const Text('At an outstation, Continental (3.13)'),
        value: _A330RestScenario.outstationContinental,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title: const Text('After a through-the-night duty (3.13)'),
        value: _A330RestScenario.throughTheNight,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title: const Text('After a westbound Intercontinental (3.13.2)'),
        value: _A330RestScenario.postIntercontinentalWestbound,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title: const Text(
            'At an outstation, after an eastbound Intercontinental (3.13)'),
        value: _A330RestScenario.outstationAfterEastbound,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330RestScenario>(
        title: const Text('Before an Intercontinental (3.13)'),
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

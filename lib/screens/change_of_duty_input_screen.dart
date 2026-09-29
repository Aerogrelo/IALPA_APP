import 'package:flutter/material.dart';

import '../models/rule_result.dart';
import '../rules/a320/change_of_duty/r01.dart';
import '../rules/a320/change_of_duty/r02.dart';
import '../rules/a320/change_of_duty/r03.dart';
import '../rules/a320/change_of_duty/r04.dart';
import '../rules/a320/change_of_duty/r05.dart';
import '../rules/a320/change_of_duty/r06.dart';
import '../rules/a320/change_of_duty/r07.dart';
import '../rules/a330/change_of_duty/verify_change_after_reporting_at_base.dart';
import '../rules/a330/change_of_duty/verify_change_at_base_day_of_operation.dart';
import '../rules/a330/change_of_duty/verify_change_at_base_with_notice.dart';
import '../rules/a330/change_of_duty/verify_change_at_outstation_day_of_operation.dart';
import 'fleet_selection_screen.dart';
import 'result_screen.dart';
import 'widgets/date_time_field.dart';

/// A320/321 clause 3.2 is organised as Continental (3.2.3) /
/// Intercontinental (3.2.4), each with several situations — one per rule
/// (R-01 through R-07).
enum _A320Scenario {
  continentalBase, // R-01, 3.2.3(a)
  continentalNotice, // R-02, 3.2.3(b)
  toStandby, // R-03, 3.2.3(c)
  standbyBroughtForward, // R-04, 3.2.3(f)
  intercontinentalBase, // R-05, 3.2.4(b)
  intercontinentalNotice, // R-06, 3.2.4(c)
  intercontinentalOutstation, // R-07, 3.2.4(f)
}

/// The A330's clause 3.2 is organised by Base / Outstation and by
/// notice/timing, one rule per situation.
enum _A330Scenario {
  baseDayOfOperation, // 3.2.4
  baseWithNotice, // 3.2.5
  afterReportingAtBase, // 3.2.6
  outstationDayOfOperation, // 3.2.9
}

/// Third screen (for Change of Duty): enter the original and proposed
/// duty times for whichever clause-3.2 situation applies, and check it
/// against Change of Duty (Group A) — 7 rules for the A320/321, 4 for the
/// A330 (see `lib/rules/*/change_of_duty/`).
///
/// Unlike [MaxDutyInputScreen] (one shape of form covers both fleets),
/// Group A has several genuinely different situations per fleet — which
/// fields matter (report time, finish time, standby start, notice given)
/// depends on which one applies. So this screen leads with a scenario
/// selector, then only shows the fields that scenario's rule actually
/// takes.
///
/// **Every rule in this group resolves to green or amber, never red** —
/// EASA does not regulate the airline's scheduling flexibility, so a
/// breach of clause 3.2 is always a contractual (OWC) matter, confirmed
/// with Elena for both fleets (29/09).
class ChangeOfDutyInputScreen extends StatefulWidget {
  const ChangeOfDutyInputScreen({super.key, required this.fleet});

  final Fleet fleet;

  @override
  State<ChangeOfDutyInputScreen> createState() =>
      _ChangeOfDutyInputScreenState();
}

class _ChangeOfDutyInputScreenState extends State<ChangeOfDutyInputScreen> {
  _A320Scenario _a320Scenario = _A320Scenario.continentalBase;
  _A330Scenario _a330Scenario = _A330Scenario.baseDayOfOperation;

  // Shared date/time fields, reused with different labels depending on
  // the selected scenario.
  DateTime _originalReport = DateTime.now().toUtc();
  DateTime _originalFinish =
      DateTime.now().toUtc().add(const Duration(hours: 10));
  DateTime _newReport = DateTime.now().toUtc();
  DateTime _newFinish =
      DateTime.now().toUtc().add(const Duration(hours: 10));

  int _noticeHours = 24;

  // Scenario-specific flags.
  bool _changeToAugmentedCrew = false;
  bool _similarDuration = true;
  bool _noticeBy2200PreviousDay = true;
  bool _pilotConsents = false;
  bool _alreadyReported = false;

  @override
  Widget build(BuildContext context) {
    final fleetLabel = widget.fleet == Fleet.a320 ? 'A320/321' : 'A330';

    return Scaffold(
      appBar: AppBar(title: Text('Change of Duty — $fleetLabel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
      RadioListTile<_A320Scenario>(
        title: const Text('Continental, day of operation, at base (3.2.3a)'),
        value: _A320Scenario.continentalBase,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320Scenario>(
        title: const Text('Continental, ≥24h notice, at base (3.2.3b)'),
        value: _A320Scenario.continentalNotice,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320Scenario>(
        title: const Text('Changed to a standby duty (3.2.3c)'),
        value: _A320Scenario.toStandby,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320Scenario>(
        title:
            const Text('Standby before 0800, brought forward (3.2.3f)'),
        value: _A320Scenario.standbyBroughtForward,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320Scenario>(
        title:
            const Text('Intercontinental, day of operation, at base (3.2.4b)'),
        value: _A320Scenario.intercontinentalBase,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320Scenario>(
        title: const Text(
            'Intercontinental, ≥14h notice, at base (3.2.4c)'),
        value: _A320Scenario.intercontinentalNotice,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      RadioListTile<_A320Scenario>(
        title: const Text(
            'Intercontinental, day of operation, at outstation (3.2.4f)'),
        value: _A320Scenario.intercontinentalOutstation,
        groupValue: _a320Scenario,
        onChanged: (value) => setState(() => _a320Scenario = value!),
      ),
      const SizedBox(height: 16),
      ..._buildA320Fields(),
    ];
  }

  List<Widget> _buildA320Fields() {
    switch (_a320Scenario) {
      case _A320Scenario.continentalBase:
        return [
          DateTimeField(
            label: 'Original report time (UTC)',
            value: _originalReport,
            onChanged: (v) => setState(() => _originalReport = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'Original finish time (UTC)',
            value: _originalFinish,
            onChanged: (v) => setState(() => _originalFinish = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'New report time (UTC)',
            value: _newReport,
            onChanged: (v) => setState(() => _newReport = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'New finish time (UTC)',
            value: _newFinish,
            onChanged: (v) => setState(() => _newFinish = v),
          ),
        ];
      case _A320Scenario.continentalNotice:
      case _A320Scenario.intercontinentalBase:
      case _A320Scenario.intercontinentalNotice:
      case _A320Scenario.intercontinentalOutstation:
        return [
          DateTimeField(
            label: 'Original report time (UTC)',
            value: _originalReport,
            onChanged: (v) => setState(() => _originalReport = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'New report time (UTC)',
            value: _newReport,
            onChanged: (v) => setState(() => _newReport = v),
          ),
          const SizedBox(height: 12),
          if (_a320Scenario == _A320Scenario.continentalNotice ||
              _a320Scenario == _A320Scenario.intercontinentalNotice)
            _buildNoticeStepper(),
          if (_a320Scenario == _A320Scenario.intercontinentalNotice)
            SwitchListTile(
              title: const Text('Pilot consents to a larger advance '
                  '(Blue Sheet OWC)'),
              value: _pilotConsents,
              onChanged: (v) => setState(() => _pilotConsents = v),
            ),
          if (_a320Scenario == _A320Scenario.intercontinentalOutstation)
            SwitchListTile(
              title: const Text('Pilot has already reported for duty'),
              value: _alreadyReported,
              onChanged: (v) => setState(() => _alreadyReported = v),
            ),
        ];
      case _A320Scenario.toStandby:
        return [
          DateTimeField(
            label: 'Original flight duty report time (UTC)',
            value: _originalReport,
            onChanged: (v) => setState(() => _originalReport = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'New standby start time (UTC)',
            value: _newReport,
            onChanged: (v) => setState(() => _newReport = v),
          ),
        ];
      case _A320Scenario.standbyBroughtForward:
        return [
          DateTimeField(
            label: 'Original standby start time (UTC)',
            value: _originalReport,
            onChanged: (v) => setState(() => _originalReport = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'New standby start time (UTC)',
            value: _newReport,
            onChanged: (v) => setState(() => _newReport = v),
          ),
          const SizedBox(height: 12),
          _buildNoticeStepper(),
        ];
    }
  }

  RuleResult _verifyA320() {
    switch (_a320Scenario) {
      case _A320Scenario.continentalBase:
        return verifyR01(
          originalReport: _originalReport,
          originalFinish: _originalFinish,
          newReport: _newReport,
          newFinish: _newFinish,
        );
      case _A320Scenario.continentalNotice:
        return verifyR02(
          originalReport: _originalReport,
          newReport: _newReport,
          noticeGiven: Duration(hours: _noticeHours),
        );
      case _A320Scenario.toStandby:
        return verifyR03(
          originalFlightReport: _originalReport,
          newStandbyStart: _newReport,
        );
      case _A320Scenario.standbyBroughtForward:
        return verifyR04(
          originalStandbyStart: _originalReport,
          newStandbyStart: _newReport,
          noticeGiven: Duration(hours: _noticeHours),
        );
      case _A320Scenario.intercontinentalBase:
        return verifyR05(
          originalReport: _originalReport,
          newReport: _newReport,
        );
      case _A320Scenario.intercontinentalNotice:
        return verifyR06(
          originalReport: _originalReport,
          newReport: _newReport,
          noticeGiven: Duration(hours: _noticeHours),
          pilotConsents: _pilotConsents,
        );
      case _A320Scenario.intercontinentalOutstation:
        return verifyR07(
          originalReport: _originalReport,
          newReport: _newReport,
          alreadyReported: _alreadyReported,
        );
    }
  }

  // ---------------------------------------------------------------------
  // A330
  // ---------------------------------------------------------------------

  List<Widget> _buildA330Form() {
    return [
      const Text('Situation', style: TextStyle(fontWeight: FontWeight.bold)),
      RadioListTile<_A330Scenario>(
        title: const Text('At base, day of operation (3.2.4)'),
        value: _A330Scenario.baseDayOfOperation,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330Scenario>(
        title: const Text('At base, ≥14h notice (3.2.5)'),
        value: _A330Scenario.baseWithNotice,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330Scenario>(
        title: const Text('At base, after reporting for duty (3.2.6)'),
        value: _A330Scenario.afterReportingAtBase,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      RadioListTile<_A330Scenario>(
        title: const Text('At outstation, day of operation (3.2.9)'),
        value: _A330Scenario.outstationDayOfOperation,
        groupValue: _a330Scenario,
        onChanged: (value) => setState(() => _a330Scenario = value!),
      ),
      const SizedBox(height: 16),
      ..._buildA330Fields(),
    ];
  }

  List<Widget> _buildA330Fields() {
    switch (_a330Scenario) {
      case _A330Scenario.baseDayOfOperation:
        return [
          DateTimeField(
            label: 'Original report time (UTC)',
            value: _originalReport,
            onChanged: (v) => setState(() => _originalReport = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'New report time (UTC)',
            value: _newReport,
            onChanged: (v) => setState(() => _newReport = v),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Change is to an augmented crew operation'),
            value: _changeToAugmentedCrew,
            onChanged: (v) => setState(() => _changeToAugmentedCrew = v),
          ),
        ];
      case _A330Scenario.baseWithNotice:
        return [
          DateTimeField(
            label: 'Original report time (UTC)',
            value: _originalReport,
            onChanged: (v) => setState(() => _originalReport = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'New report time (UTC)',
            value: _newReport,
            onChanged: (v) => setState(() => _newReport = v),
          ),
          const SizedBox(height: 12),
          _buildNoticeStepper(),
          SwitchListTile(
            title: const Text('New duty is of similar duration'),
            value: _similarDuration,
            onChanged: (v) => setState(() => _similarDuration = v),
          ),
          SwitchListTile(
            title: const Text('Notice given by 22:00 the previous day'),
            value: _noticeBy2200PreviousDay,
            onChanged: (v) => setState(() => _noticeBy2200PreviousDay = v),
          ),
          SwitchListTile(
            title: const Text('Pilot consents to a larger advance'),
            value: _pilotConsents,
            onChanged: (v) => setState(() => _pilotConsents = v),
          ),
        ];
      case _A330Scenario.afterReportingAtBase:
        return [
          DateTimeField(
            label: 'Original finish time (UTC)',
            value: _originalFinish,
            onChanged: (v) => setState(() => _originalFinish = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'New finish time (UTC)',
            value: _newFinish,
            onChanged: (v) => setState(() => _newFinish = v),
          ),
        ];
      case _A330Scenario.outstationDayOfOperation:
        return [
          DateTimeField(
            label: 'Original report time (UTC)',
            value: _originalReport,
            onChanged: (v) => setState(() => _originalReport = v),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'New report time (UTC)',
            value: _newReport,
            onChanged: (v) => setState(() => _newReport = v),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Pilot has already reported for duty'),
            value: _alreadyReported,
            onChanged: (v) => setState(() => _alreadyReported = v),
          ),
        ];
    }
  }

  RuleResult _verifyA330() {
    switch (_a330Scenario) {
      case _A330Scenario.baseDayOfOperation:
        return verifyChangeAtBaseDayOfOperation(
          originalReport: _originalReport,
          newReport: _newReport,
          changeToAugmentedCrewOperation: _changeToAugmentedCrew,
        );
      case _A330Scenario.baseWithNotice:
        return verifyChangeAtBaseWithNotice(
          originalReport: _originalReport,
          newReport: _newReport,
          noticeGiven: Duration(hours: _noticeHours),
          similarDuration: _similarDuration,
          noticeGivenBy2200PreviousDay: _noticeBy2200PreviousDay,
          pilotConsents: _pilotConsents,
        );
      case _A330Scenario.afterReportingAtBase:
        return verifyChangeAfterReportingAtBase(
          originalFinish: _originalFinish,
          newFinish: _newFinish,
        );
      case _A330Scenario.outstationDayOfOperation:
        return verifyChangeAtOutstationDayOfOperation(
          originalReport: _originalReport,
          newReport: _newReport,
          alreadyReported: _alreadyReported,
        );
    }
  }

  // ---------------------------------------------------------------------
  // Shared
  // ---------------------------------------------------------------------

  Widget _buildNoticeStepper() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Text('Notice given: '),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _noticeHours > 0
                ? () => setState(() => _noticeHours--)
                : null,
          ),
          Text('${_noticeHours}h'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => setState(() => _noticeHours++),
          ),
        ],
      ),
    );
  }

  void _verify() {
    final result =
        widget.fleet == Fleet.a320 ? _verifyA320() : _verifyA330();

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/duty.dart';
import '../models/rule_result.dart';
import '../rules/a320/max_duty/r14.dart';
import '../rules/a320/max_duty/r15.dart';
import '../rules/a330/max_duty/verify_max_duty.dart';
import 'fleet_selection_screen.dart';
import 'result_screen.dart';
import 'widgets/date_time_field.dart';
import 'widgets/roster_import_button.dart';

enum _A320FlightType { continental, intercontinental }

/// A320/321 only for now (29/09) — the fleet whose rules (R-14/R-15) expose
/// [stbhPortion]/[stbaPortion]. The A330's [verifyA330MaxDuty] has no
/// equivalent parameter yet, so a preceding standby isn't modelled for that
/// fleet — flagged in its section of the form below.
enum _PrecedingStandby { none, stbh, stba }

/// Second screen: enter a duty's report/end time (plus the handful of
/// fleet-specific fields each rule needs) and check it against Maximum
/// Flight Duty Time — R-14/R-15 (clause 3.11) for the A320/321, or
/// [verifyA330MaxDuty] (clause 3.10) for the A330.
///
/// v1.0 scope note (29/09): this is the FIRST end-to-end screen built for
/// the app — proof that a duty entered here really runs through the same
/// rule engine already verified by `flutter test`, all the way to a
/// 3-color result. Change of Duty (Group A) and Minimum Rest (Group B)
/// screens are the natural next step, reusing this same shape.
///
/// **Time zone (29/09):** all times entered here are treated as UTC —
/// pilots think in Zulu time for duty hours, not the device's local time
/// zone, and the convenio's own report/end time bands (e.g. the
/// 0100-0629 night window) are meant to be read that way too. The date
/// and time pickers just collect wall-clock digits; [DateTimeField]
/// builds the resulting [DateTime] with [DateTime.utc] so no implicit
/// local-time conversion ever happens.
///
/// For the A330, the finer WOCL-encroachment fields
/// (`woclEncroachment`, `dutyStartsInWocl`, `extensionInvadesWocl`) are
/// NOT exposed in this first version — they default to "no WOCL
/// encroachment", which undercounts the reduction for augmented-crew
/// duties that actually cross 0200-0559. Flagged in the UI and here for
/// the next pass.
///
/// **Preceding standby (29/09):** the A320/321 section asks whether the
/// duty was preceded by a Standby at Home (STBH, counts at 50%, 3.17.2c)
/// or a Standby at the Airport (STBA, counts in full, 2.16.1b), and if so,
/// when that standby started. The elapsed time from there to report is
/// passed straight to R-14/R-15 as `stbhPortion`/`stbaPortion` — each rule
/// applies its own percentage downstream in `effectiveFlightDutyTime`, so
/// this screen only computes the raw elapsed time, never the halved
/// figure. Not yet available for the A330 — see the note above.
class MaxDutyInputScreen extends StatefulWidget {
  const MaxDutyInputScreen({super.key, required this.fleet});

  final Fleet fleet;

  @override
  State<MaxDutyInputScreen> createState() => _MaxDutyInputScreenState();
}

class _MaxDutyInputScreenState extends State<MaxDutyInputScreen> {
  DateTime _report = DateTime.now().toUtc();
  DateTime _end = DateTime.now().toUtc().add(const Duration(hours: 10));

  // A320/321 fields.
  _A320FlightType _a320FlightType = _A320FlightType.continental;
  int _sectors = 1;
  bool _eastbound = false;
  bool _deadheading = false;
  _PrecedingStandby _precedingStandby = _PrecedingStandby.none;
  DateTime _standbyStart =
      DateTime.now().toUtc().subtract(const Duration(hours: 2));

  // A330 fields.
  A330CrewType _crewType = A330CrewType.twoPilot;
  bool _delayed = false;
  TransatlanticDirection _direction = TransatlanticDirection.none;
  bool _throughTheNight = false;
  bool _agreedCockpitRestArea = true;

  @override
  Widget build(BuildContext context) {
    final fleetLabel = widget.fleet == Fleet.a320 ? 'A320/321' : 'A330';

    return Scaffold(
      appBar: AppBar(title: Text('Maximum Duty — $fleetLabel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 29/09: fills report/end from the pilot's roster PDF instead
          // of typing it in — same roster-import service used on the
          // Change of Duty screen.
          RosterImportButton(
            onImported: (report, finish) => setState(() {
              _report = report;
              _end = finish;
            }),
          ),
          const SizedBox(height: 16),
          DateTimeField(
            label: 'Start time (report, UTC)',
            value: _report,
            onChanged: (value) => setState(() => _report = value),
          ),
          const SizedBox(height: 12),
          DateTimeField(
            label: 'End time (UTC)',
            value: _end,
            onChanged: (value) => setState(() => _end = value),
          ),
          const SizedBox(height: 24),
          if (widget.fleet == Fleet.a320) _buildA320Fields(),
          if (widget.fleet == Fleet.a330) _buildA330Fields(),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _verify,
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Widget _buildA320Fields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Flight type',
            style: TextStyle(fontWeight: FontWeight.bold)),
        RadioListTile<_A320FlightType>(
          title: const Text('Continental (3.11.1)'),
          value: _A320FlightType.continental,
          groupValue: _a320FlightType,
          onChanged: (value) => setState(() => _a320FlightType = value!),
        ),
        RadioListTile<_A320FlightType>(
          title: const Text('Intercontinental (3.11.2)'),
          value: _A320FlightType.intercontinental,
          groupValue: _a320FlightType,
          onChanged: (value) => setState(() => _a320FlightType = value!),
        ),
        if (_a320FlightType == _A320FlightType.continental) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Sectors: '),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed:
                    _sectors > 1 ? () => setState(() => _sectors--) : null,
              ),
              Text('$_sectors'),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _sectors++),
              ),
            ],
          ),
        ] else ...[
          SwitchListTile(
            title: const Text('Eastbound Transatlantic'),
            value: _eastbound,
            onChanged: (value) => setState(() => _eastbound = value),
          ),
          SwitchListTile(
            title: const Text('Includes deadheading'),
            value: _deadheading,
            onChanged: (value) => setState(() => _deadheading = value),
          ),
        ],
        const SizedBox(height: 16),
        const Text('Preceded by standby?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        RadioListTile<_PrecedingStandby>(
          title: const Text('None'),
          value: _PrecedingStandby.none,
          groupValue: _precedingStandby,
          onChanged: (value) => setState(() => _precedingStandby = value!),
        ),
        RadioListTile<_PrecedingStandby>(
          title: const Text('Standby at Home (STBH) — counts at 50%'),
          value: _PrecedingStandby.stbh,
          groupValue: _precedingStandby,
          onChanged: (value) => setState(() => _precedingStandby = value!),
        ),
        RadioListTile<_PrecedingStandby>(
          title: const Text('Standby at the Airport (STBA) — counts in '
              'full'),
          value: _PrecedingStandby.stba,
          groupValue: _precedingStandby,
          onChanged: (value) => setState(() => _precedingStandby = value!),
        ),
        if (_precedingStandby != _PrecedingStandby.none) ...[
          const SizedBox(height: 4),
          DateTimeField(
            label: 'Standby start time (UTC)',
            value: _standbyStart,
            onChanged: (value) => setState(() => _standbyStart = value),
          ),
          const SizedBox(height: 4),
          Text(
            _precedingStandby == _PrecedingStandby.stbh
                ? 'Elapsed: ${_fmtDuration(_standbyElapsed)} — counts as '
                    '${_fmtDuration(Duration(minutes: _standbyElapsed.inMinutes ~/ 2))} '
                    'towards the duty (50%).'
                : 'Elapsed: ${_fmtDuration(_standbyElapsed)} — counts in '
                    'full towards the duty (100%).',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ],
    );
  }

  /// The raw time between the standby's start and this duty's report, never
  /// negative (a standby start after report would mean no elapsed portion).
  Duration get _standbyElapsed {
    final elapsed = _report.difference(_standbyStart);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// The portion of the preceding standby that actually counts towards the
  /// duty's effective flight duty time — STBH is halved downstream in
  /// [effectiveFlightDutyTime], STBA counts in full, so both are passed the
  /// same raw elapsed time and let the rule apply its own percentage.
  Duration get _standbyPortion =>
      _precedingStandby == _PrecedingStandby.none
          ? Duration.zero
          : _standbyElapsed;

  String _fmtDuration(Duration d) {
    final hours = d.inMinutes ~/ 60;
    final minutes = d.inMinutes % 60;
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }

  Widget _buildA330Fields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Crew', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<A330CrewType>(
          value: _crewType,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: A330CrewType.twoPilot,
              child: Text('Two pilots'),
            ),
            DropdownMenuItem(
              value: A330CrewType.augmented,
              child: Text('Augmented'),
            ),
            DropdownMenuItem(
              value: A330CrewType.heavy,
              child: Text('Heavy'),
            ),
          ],
          onChanged: (value) => setState(() => _crewType = value!),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Delayed duty (applies the 3.10 extension)'),
          value: _delayed,
          onChanged: (value) => setState(() => _delayed = value),
        ),
        const Text('Transatlantic direction',
            style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<TransatlanticDirection>(
          value: _direction,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: TransatlanticDirection.none,
              child: Text('None'),
            ),
            DropdownMenuItem(
              value: TransatlanticDirection.eastbound,
              child: Text('Eastbound'),
            ),
            DropdownMenuItem(
              value: TransatlanticDirection.westbound,
              child: Text('Westbound'),
            ),
          ],
          onChanged: (value) => setState(() => _direction = value!),
        ),
        if (_crewType == A330CrewType.twoPilot)
          SwitchListTile(
            title: const Text('Through-the-night'),
            value: _throughTheNight,
            onChanged: (value) => setState(() => _throughTheNight = value),
          ),
        if (_crewType == A330CrewType.augmented)
          SwitchListTile(
            title: const Text('Agreed cockpit rest area'),
            value: _agreedCockpitRestArea,
            onChanged: (value) =>
                setState(() => _agreedCockpitRestArea = value),
          ),
        const SizedBox(height: 8),
        const Text(
          'Note: the fine-grained WOCL-encroachment settings (02:00-05:59) '
          "aren't on this screen yet — no encroachment is assumed for now. "
          'A preceding standby (STBH/STBA) also isn\'t modelled for the '
          'A330 yet. Coming in a future update.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  void _verify() {
    if (!_end.isAfter(_report)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after the start time.'),
        ),
      );
      return;
    }

    final result =
        widget.fleet == Fleet.a320 ? _verifyA320() : _verifyA330();

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    );
  }

  RuleResult _verifyA320() {
    final stbhPortion = _precedingStandby == _PrecedingStandby.stbh
        ? _standbyPortion
        : Duration.zero;
    final stbaPortion = _precedingStandby == _PrecedingStandby.stba
        ? _standbyPortion
        : Duration.zero;

    if (_a320FlightType == _A320FlightType.continental) {
      final duty = Duty(
        report: _report,
        end: _end,
        type: DutyType.flight,
        sectors: _sectors,
      );
      return verifyR14(
        duty: duty,
        stbhPortion: stbhPortion,
        stbaPortion: stbaPortion,
      );
    }

    final duty = Duty(
      report: _report,
      end: _end,
      type: DutyType.flight,
      deadheading: _deadheading,
      transatlanticDirection: _eastbound
          ? TransatlanticDirection.eastbound
          : TransatlanticDirection.none,
    );
    return verifyR15(
      duty: duty,
      stbhPortion: stbhPortion,
      stbaPortion: stbaPortion,
    );
  }

  RuleResult _verifyA330() {
    final duty = Duty(
      report: _report,
      end: _end,
      type: DutyType.flight,
      transatlanticDirection: _direction,
    );
    return verifyA330MaxDuty(
      duty: duty,
      crewType: _crewType,
      delayed: _delayed,
      agreedCockpitRestArea: _agreedCockpitRestArea,
      direction:
          _direction == TransatlanticDirection.none ? null : _direction,
      throughTheNight: _throughTheNight,
    );
  }
}

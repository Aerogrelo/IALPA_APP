import 'package:flutter/material.dart';

import '../batch/master_roster_audit.dart';
import '../models/roster_day.dart';
import '../models/rule_result.dart';
import '../rules/a330/max_duty/verify_max_duty.dart';

/// The review screen Elena asked for (01/10): "en vez de marcar necesita
/// revisión, podríamos poner algo como especificar tripulación? que sea
/// claro que es algo que hay que aportar para que se pueda analizar."
///
/// Shows ONLY the days the batch engine couldn't verify on its own
/// (`Finding.needsInput`) — the rest of the roster (green/red/amber) is
/// never touched here, exactly as agreed. For each one it says in plain
/// words what's missing and lets the reviewer supply it (crew type via a
/// dropdown; finish time via a time picker), then re-runs JUST that
/// pilot's checks with the fix applied — turning that finding (and any
/// other finding that depended on the same missing value, e.g. the
/// Minimum Rest check for the day right after it) into a real
/// green/amber/red verdict.
///
/// Fixes are kept in memory only, for this review session — there's no
/// persistence yet (the PDF/JSON pipeline is still run by hand). Once
/// IALPA is happy with a review pass, re-exporting what was filled in is
/// a natural next step, not built here.
class MasterRosterReviewScreen extends StatefulWidget {
  const MasterRosterReviewScreen({
    super.key,
    required this.pilots,
    required this.fleet,
  });

  final List<PilotRecord> pilots;
  final AuditFleet fleet;

  @override
  State<MasterRosterReviewScreen> createState() =>
      _MasterRosterReviewScreenState();
}

class _MasterRosterReviewScreenState extends State<MasterRosterReviewScreen> {
  late List<PilotRecord> _pilots;
  late List<Finding> _findings;
  // (pilotKey, date) -> crew type the reviewer picked for that day.
  final Map<String, A330CrewType> _crewTypeOverrides = {};
  int _tab = 0; // 0 = needs input, 1 = breaches (red/amber)

  @override
  void initState() {
    super.initState();
    _pilots = List.of(widget.pilots);
    _findings = _auditAll(_pilots);
  }

  String _pilotKey(PilotRecord p) => p.id ?? p.name;

  List<Finding> _auditAll(List<PilotRecord> pilots) {
    final all = <Finding>[];
    for (final pilot in pilots) {
      final overrides = <String, A330CrewType>{};
      _crewTypeOverrides.forEach((key, value) {
        final parts = key.split('|');
        if (parts[0] == _pilotKey(pilot)) overrides[parts[1]] = value;
      });
      all.addAll(auditPilotMaxDuty(pilot, widget.fleet, crewTypeOverrides: overrides));
      all.addAll(auditPilotMinRest(pilot, widget.fleet));
    }
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final needsInput = _findings.where((f) => f.needsInput).toList();
    final breaches = _findings.where((f) =>
        f.result != null &&
        (f.result!.color == RuleColor.red || f.result!.color == RuleColor.amber));
    final green = _findings.where((f) => f.result?.color == RuleColor.green).length;
    final skipped = _findings.where((f) => f.skipped).length;

    final grouped = _groupByInput(needsInput);

    return Scaffold(
      appBar: AppBar(title: const Text('Master Roster Review')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _Stat(label: 'Pilots', value: '${_pilots.length}'),
                _Stat(label: 'Green', value: '$green', color: Colors.green),
                _Stat(
                  label: 'Breaches',
                  value: '${breaches.length}',
                  color: Colors.red,
                ),
                _Stat(
                  label: 'Needs input',
                  value: '${needsInput.length}',
                  color: Colors.orange,
                ),
                _Stat(label: 'Not applicable', value: '$skipped'),
              ],
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    label: 'Needs input (${grouped.length})',
                    selected: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    label: 'Breaches (${breaches.length})',
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _tab == 0
                ? _buildNeedsInputList(grouped)
                : _buildBreachesList(breaches.toList()),
          ),
        ],
      ),
    );
  }

  /// Groups needsInput findings by (pilot, the day actually missing
  /// data) — see [Finding.inputDate]. One card per group: a reviewer
  /// fills that day in once, even if it's blocking more than one check
  /// (its own Max Duty AND the Minimum Rest for the day after it).
  Map<String, List<Finding>> _groupByInput(List<Finding> findings) {
    final map = <String, List<Finding>>{};
    for (final f in findings) {
      final key = '${f.pilotId ?? f.pilotName}|${f.inputDate}';
      map.putIfAbsent(key, () => []).add(f);
    }
    return map;
  }

  Widget _buildNeedsInputList(Map<String, List<Finding>> grouped) {
    if (grouped.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Nothing pending — every day the engine couldn't verify on "
            'its own already has its data filled in.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final entries = grouped.entries.toList();
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final key = entries[i].key;
        final group = entries[i].value;
        final parts = key.split('|');
        final pilotKey = parts[0];
        final date = parts[1];
        final pilot = _pilots.firstWhere(
          (p) => _pilotKey(p) == pilotKey,
          orElse: () => group.isNotEmpty
              ? PilotRecord(name: group.first.pilotName, id: group.first.pilotId, days: const {})
              : throw StateError('no pilot for $pilotKey'),
        );
        return _NeedsInputCard(
          key: ValueKey(key),
          pilot: pilot,
          date: date,
          findings: group,
          fleet: widget.fleet,
          onSubmit: _applyFix,
        );
      },
    );
  }

  Widget _buildBreachesList(List<Finding> breaches) {
    if (breaches.isEmpty) {
      return const Center(
        child: Text('No breaches among the days already verified.'),
      );
    }
    breaches.sort((a, b) {
      final ar = a.result!.color == RuleColor.red ? 0 : 1;
      final br = b.result!.color == RuleColor.red ? 0 : 1;
      return ar.compareTo(br);
    });
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: breaches.length,
      itemBuilder: (context, i) {
        final f = breaches[i];
        final isRed = f.result!.color == RuleColor.red;
        return Card(
          color: isRed ? Colors.red.shade50 : Colors.amber.shade50,
          child: ListTile(
            leading: Icon(
              isRed ? Icons.cancel : Icons.warning_amber,
              color: isRed ? Colors.red : Colors.amber.shade800,
            ),
            title: Text('${f.pilotName} — ${f.date} — '
                '${f.kind == FindingKind.maxDuty ? "Maximum Flight Duty Time" : "Minimum Rest"}'),
            subtitle: Text('${f.result!.clause}: ${f.result!.explanation}'),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  /// Patches the given day in [pilot]'s record with whatever the
  /// reviewer supplied, then re-audits JUST that one pilot (cheap — a
  /// couple of weeks of days) and swaps its findings back into the full
  /// list. Everyone else's results are untouched.
  void _applyFix(
    PilotRecord pilot,
    String date, {
    A330CrewType? crewType,
    DateTime? finishTimeUtc,
  }) {
    final originalDay = pilot.days[date];
    if (originalDay == null) return;

    final patchedDay = finishTimeUtc != null
        ? originalDay.copyWith(status: 'ok', trailingTimeUtc: finishTimeUtc)
        : originalDay;

    final newDays = Map<String, RosterDay>.from(pilot.days)..[date] = patchedDay;
    final newPilot = PilotRecord(name: pilot.name, id: pilot.id, days: newDays);

    setState(() {
      if (crewType != null) {
        _crewTypeOverrides['${_pilotKey(pilot)}|$date'] = crewType;
      }
      final idx = _pilots.indexWhere((p) => _pilotKey(p) == _pilotKey(pilot));
      if (idx != -1) _pilots[idx] = newPilot;

      final overrides = <String, A330CrewType>{};
      _crewTypeOverrides.forEach((key, value) {
        final parts = key.split('|');
        if (parts[0] == _pilotKey(newPilot)) overrides[parts[1]] = value;
      });
      final newFindings = [
        ...auditPilotMaxDuty(newPilot, widget.fleet, crewTypeOverrides: overrides),
        ...auditPilotMinRest(newPilot, widget.fleet),
      ];
      _findings.removeWhere((f) => (f.pilotId ?? f.pilotName) == _pilotKey(newPilot));
      _findings.addAll(newFindings);
    });
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// One card per (pilot, day missing data) — see
/// [_MasterRosterReviewScreenState._groupByInput]. Shows every reason
/// that day is blocking a check, with one input per distinct missing
/// field (a day can need BOTH crew type and finish time at once — every
/// transatlantic A330 day with the overnight-continuation gap does).
class _NeedsInputCard extends StatefulWidget {
  const _NeedsInputCard({
    super.key,
    required this.pilot,
    required this.date,
    required this.findings,
    required this.fleet,
    required this.onSubmit,
  });

  final PilotRecord pilot;
  final String date;
  final List<Finding> findings;
  final AuditFleet fleet;
  final void Function(
    PilotRecord pilot,
    String date, {
    A330CrewType? crewType,
    DateTime? finishTimeUtc,
  }) onSubmit;

  @override
  State<_NeedsInputCard> createState() => _NeedsInputCardState();
}

class _NeedsInputCardState extends State<_NeedsInputCard> {
  A330CrewType? _crewType;
  TimeOfDay? _finishTime;
  bool _crossesMidnight = true; // the gap this exists for IS the overnight case

  @override
  Widget build(BuildContext context) {
    final day = widget.pilot.days[widget.date];
    final allMissing = widget.findings.expand((f) => f.missingFields).toSet();
    final needsCrewType = allMissing.contains('crewType');
    final needsFinishTime = allMissing.contains('finishTime');
    final unresolved = allMissing.contains('unresolved');

    final checksBlocked = widget.findings
        .map((f) => f.kind == FindingKind.maxDuty ? 'Maximum Flight Duty Time' : 'Minimum Rest')
        .toSet()
        .join(' + ');

    final canSubmit = (!needsCrewType || _crewType != null) &&
        (!needsFinishTime || _finishTime != null) &&
        !unresolved;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.pilot.name} — ${widget.date}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text('Blocks: $checksBlocked',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (day?.reportTime != null) ...[
              const SizedBox(height: 4),
              Text('Roster start time: ${day!.reportTime} (Dublin local time)',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            const SizedBox(height: 12),
            if (unresolved)
              const Text(
                "The engine couldn't identify this day at all — "
                'check it directly against the original PDF.',
                style: TextStyle(color: Colors.red),
              ),
            if (needsCrewType) ...[
              const Text('Crew type',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              DropdownButton<A330CrewType>(
                value: _crewType,
                hint: const Text('Choose...'),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: A330CrewType.twoPilot,
                    child: Text('Two-pilot'),
                  ),
                  DropdownMenuItem(
                    value: A330CrewType.augmented,
                    child: Text('Augmented (3 pilots)'),
                  ),
                  DropdownMenuItem(
                    value: A330CrewType.heavy,
                    child: Text('Heavy (4 pilots)'),
                  ),
                ],
                onChanged: (v) => setState(() => _crewType = v),
              ),
              const SizedBox(height: 12),
            ],
            if (needsFinishTime) ...[
              const Text('Duty finish time (Dublin local time)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(_finishTime == null
                        ? 'Choose time'
                        : _finishTime!.format(context)),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _finishTime ?? const TimeOfDay(hour: 6, minute: 0),
                      );
                      if (picked != null) setState(() => _finishTime = picked);
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Finishes the next day',
                          style: TextStyle(fontSize: 12)),
                      value: _crossesMidnight,
                      onChanged: (v) => setState(() => _crossesMidnight = v ?? true),
                    ),
                  ),
                ],
              ),
              const Text(
                "The roster only shows this duty's start time — it's a "
                "long-haul flight finishing the next day, and the roster "
                "doesn't print the arrival time. Check it against the crew "
                "notice or with the pilot.",
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 12),
            ],
            if (!unresolved)
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: canSubmit ? _submit : null,
                  child: const Text('Verify'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final day = widget.pilot.days[widget.date];
    DateTime? finishUtc;
    if (_finishTime != null) {
      finishUtc = _computeFinishUtc(day, _finishTime!, _crossesMidnight);
      if (finishUtc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't compute the UTC time — this day's "
                "start time is missing from the roster."),
          ),
        );
        return;
      }
    }
    widget.onSubmit(
      widget.pilot,
      widget.date,
      crewType: _crewType,
      finishTimeUtc: finishUtc,
    );
  }

  /// Converts the reviewer's local finish time to UTC using the SAME
  /// Dublin UTC offset as this day's own report time (which the Python
  /// pipeline already converted, from the roster's confirmed "ALL Times
  /// in LOCAL BASE" header — see build_rosterday_json.py). Good for the
  /// normal case (report and finish are only hours apart, well within
  /// the same IST/GMT period); a duty that happens to straddle the
  /// twice-a-year DST change is the one case this would get an hour
  /// wrong — rare enough, and checkable against the original roster, not
  /// worth a full timezone dependency for an internal review tool.
  DateTime? _computeFinishUtc(RosterDay? day, TimeOfDay finishTime, bool crossesMidnight) {
    final reportUtc = day?.reportTimeUtc;
    final reportLocal = day?.reportTime;
    if (reportUtc == null || reportLocal == null) return null;

    final localParts = reportLocal.split(':');
    final reportLocalMinutes =
        int.parse(localParts[0]) * 60 + int.parse(localParts[1]);
    final reportUtcMinutes = reportUtc.hour * 60 + reportUtc.minute;
    var offsetMinutes = reportLocalMinutes - reportUtcMinutes;
    if (offsetMinutes > 90) offsetMinutes -= 24 * 60;
    if (offsetMinutes < -30) offsetMinutes += 24 * 60;

    var finishLocalMinutes = finishTime.hour * 60 + finishTime.minute;
    if (crossesMidnight) finishLocalMinutes += 24 * 60;

    final finishUtcMinutes = finishLocalMinutes - offsetMinutes;
    final reportUtcMidnight = DateTime.utc(reportUtc.year, reportUtc.month, reportUtc.day);
    return reportUtcMidnight.add(Duration(minutes: finishUtcMinutes));
  }
}

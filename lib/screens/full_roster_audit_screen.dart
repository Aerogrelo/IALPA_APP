import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../batch/master_roster_audit.dart';
import '../services/roster_service.dart';
import 'fleet_selection_screen.dart';
import 'master_roster_review_screen.dart';

/// "Full roster audit" (01/10) — a pilot's own answer to the question
/// IALPA's Master Roster tool asks at fleet scale: not "does this one
/// change comply?" (Change of Duty) but "is every day of MY published
/// roster, as it stands right now, within Maximum Duty and Minimum
/// Rest?". Elena's own words for wanting this (30/09, about the IALPA
/// tool): "es muy interesante q la app avise de incumplimientos en el
/// roster original" — this screen is that idea, scoped to the pilot's
/// own roster rather than every pilot's. Scope agreed with Elena (01/10):
/// Operating (Section 3) only, same clauses the rest of the app already
/// checks — not Planning (Section 2), which is a different audience/use
/// case (how the roster SHOULD have been built, not whether the pilot
/// can fly it as published).
///
/// Deliberately thin: this screen's only job is turning an uploaded
/// individual-roster PDF into a single [PilotRecord] (reusing the exact
/// same cloud parsing service — `uploadRosterPdf` — the other screens'
/// "Import from roster" button already calls) and handing it to
/// [MasterRosterReviewScreen], which already does everything else
/// (Max Duty + Min Rest for every day, the Needs input / Breaches
/// review UI, filling in gaps like a missing finish time or A330 crew
/// type) — built for IALPA's Master Roster tool earlier the same day,
/// and reused here completely unchanged, just with a list of one pilot
/// instead of 247.
class FullRosterAuditScreen extends StatefulWidget {
  const FullRosterAuditScreen({super.key, required this.fleet});

  final Fleet fleet;

  @override
  State<FullRosterAuditScreen> createState() => _FullRosterAuditScreenState();
}

class _FullRosterAuditScreenState extends State<FullRosterAuditScreen> {
  int _year = DateTime.now().toUtc().year;
  bool _loading = false;
  String? _error;

  AuditFleet get _auditFleet =>
      widget.fleet == Fleet.a320 ? AuditFleet.a320 : AuditFleet.a330;

  @override
  Widget build(BuildContext context) {
    final fleetLabel = widget.fleet == Fleet.a320 ? 'A320/321' : 'A330';
    return Scaffold(
      appBar: AppBar(title: Text('$fleetLabel — Full Roster Audit')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Checks every day on your own published roster against '
              'Maximum Flight Duty Time and Minimum Rest — not just a '
              'single change. Upload your roster PDF below.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            const Text('Year', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              "The roster doesn't print a year on its day-grid header — "
              'check this matches before uploading.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed:
                      _loading ? null : () => setState(() => _year--),
                ),
                Text('$_year', style: const TextStyle(fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed:
                      _loading ? null : () => setState(() => _year++),
                ),
              ],
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loading ? null : _pickAndAnalyze,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_loading ? 'Reading roster…' : 'Upload roster (PDF)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndAnalyze() async {
    setState(() => _error = null);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;

    setState(() => _loading = true);
    try {
      final Uint8List bytes = file.bytes!;
      final daysJson = await uploadRosterPdf(bytes, file.name, year: _year);
      final sortedDays = _sortedByDayMonth(daysJson);

      final pilot = PilotRecord.fromJson({
        'name': 'My roster',
        'id': null,
        'days': sortedDays,
      });

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MasterRosterReviewScreen(
            pilots: [pilot],
            fleet: _auditFleet,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Could not read that roster: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The service returns days keyed by the roster's own 'DD/MM' column
  /// label — re-sort chronologically before handing this to the batch
  /// engine. [auditPilotMinRest] walks the days in map-iteration order
  /// to compare each duty against the one right before it, so getting
  /// this order right is a correctness issue, not cosmetic (unlike the
  /// existing roster-import day picker, which only re-sorts for display
  /// — see `roster_import_button.dart`). Same single-year assumption the
  /// rest of the import flow already makes: one upload = one roster
  /// period within the chosen calendar year, never spanning Dec->Jan.
  Map<String, dynamic> _sortedByDayMonth(Map<String, dynamic> days) {
    final entries = days.entries.toList()
      ..sort((a, b) => _dayMonthKey(a.key).compareTo(_dayMonthKey(b.key)));
    return {for (final e in entries) e.key: e.value};
  }

  int _dayMonthKey(String key) {
    final parts = key.split('/');
    final day = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return month * 100 + day;
  }
}

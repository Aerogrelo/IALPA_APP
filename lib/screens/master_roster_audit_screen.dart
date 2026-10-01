import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../batch/master_roster_audit.dart';
import 'master_roster_review_screen.dart';

/// Internal IALPA tool (01/10) — NOT part of the pilot-facing flow that
/// starts at [FleetSelectionScreen]. Lets an IALPA reviewer pick the
/// `*_rosterday.json` file produced by the Python pipeline
/// (`roster_service/master_roster/` — parse -> classify -> enrich ->
/// build, see that folder's scripts) for ONE Master Roster (one fleet +
/// one rank, published separately — confirmed with Elena 01/10), choose
/// which fleet it is, and run the batch legality check (Maximum Duty +
/// Minimum Rest only — this checks the roster AS PUBLISHED, never
/// Change of Duty, which needs two roster snapshots to compare).
class MasterRosterAuditScreen extends StatefulWidget {
  const MasterRosterAuditScreen({super.key});

  @override
  State<MasterRosterAuditScreen> createState() =>
      _MasterRosterAuditScreenState();
}

class _MasterRosterAuditScreenState extends State<MasterRosterAuditScreen> {
  AuditFleet _fleet = AuditFleet.a330;
  String? _fileName;
  List<PilotRecord>? _pilots;
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IALPA — Master Roster Audit')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Checks whether a published Master Roster (every pilot in "
              "one fleet and rank) complies with Maximum Flight Duty Time "
              "and Minimum Rest. Doesn't compare changes — each pilot does "
              "that with their own roster in the app.",
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            const Text('Fleet / rank for this roster',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<AuditFleet>(
              segments: const [
                ButtonSegment(value: AuditFleet.a320, label: Text('A320/321')),
                ButtonSegment(value: AuditFleet.a330, label: Text('A330')),
              ],
              selected: {_fleet},
              onSelectionChanged: (s) => setState(() => _fleet = s.first),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loading ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: Text(_fileName ?? 'Choose *_rosterday.json file'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_pilots == null || _loading) ? null : _runAudit,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Analyze roster'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    // FileType.custom + allowedExtensions greys the file out in the
    // Windows picker on Flutter Web for some users (01/10, found testing
    // with Elena) — use FileType.any instead and just check the
    // extension ourselves after picking.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;
    if (!file.name.toLowerCase().endsWith('.json')) {
      setState(() => _error = '"${file.name}" is not a .json file');
      return;
    }
    try {
      final text = utf8.decode(file.bytes!);
      final raw = json.decode(text) as List<dynamic>;
      final pilots =
          raw.map((p) => PilotRecord.fromJson(p as Map<String, dynamic>)).toList();
      setState(() {
        _fileName = '${file.name} (${pilots.length} pilots)';
        _pilots = pilots;
      });
    } catch (e) {
      setState(() {
        _fileName = null;
        _pilots = null;
        _error = 'Could not read the file: $e';
      });
    }
  }

  void _runAudit() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MasterRosterReviewScreen(
          pilots: _pilots!,
          fleet: _fleet,
        ),
      ),
    );
  }
}

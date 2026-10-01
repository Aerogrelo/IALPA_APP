/// CLI entry point for the Master Roster batch audit (01/10).
///
/// Usage:
///   dart run bin/audit_master_roster.dart <rosterday.json> <a320|a330> [out.json]
///
/// <rosterday.json> is the output of the Python pipeline
/// (roster_service/master_roster/build_rosterday_json.py — see that
/// script's own header for the full parse -> classify -> enrich -> build
/// chain) — a JSON array of {name, id, days: {date: RosterDay-shaped}}.
///
/// Prints a one-line-per-pilot-day summary count (red/amber/green/needs
/// input/skipped) to stdout, and writes every individual finding to
/// [out.json] (default: 'audit_report.json') for IALPA to open and work
/// through — breaches (red/amber) first, then needs-input, then skipped,
/// then green.
import 'dart:convert';
import 'dart:io';

import 'package:ialpa_app/batch/master_roster_audit.dart';
import 'package:ialpa_app/models/rule_result.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run bin/audit_master_roster.dart <rosterday.json> '
      '<a320|a330> [out.json]',
    );
    exit(64);
  }

  final inPath = args[0];
  final fleetArg = args[1].toLowerCase();
  final outPath = args.length > 2 ? args[2] : 'audit_report.json';

  final fleet = switch (fleetArg) {
    'a320' => AuditFleet.a320,
    'a330' => AuditFleet.a330,
    _ => throw ArgumentError('fleet must be "a320" or "a330", got "$fleetArg"'),
  };

  final raw = json.decode(File(inPath).readAsStringSync()) as List<dynamic>;
  final pilots = raw
      .map((p) => PilotRecord.fromJson(p as Map<String, dynamic>))
      .toList();

  final summary = auditMasterRoster(pilots, fleet);

  stdout.writeln('Audited ${pilots.length} pilots, fleet=$fleetArg');
  stdout.writeln('  RED (EASA breach):      ${summary.red}');
  stdout.writeln('  AMBER (OWC, agreement): ${summary.amber}');
  stdout.writeln('  GREEN (compliant):      ${summary.green}');
  stdout.writeln('  Needs input (missing data): ${summary.needsInput}');
  stdout.writeln('  Skipped (not applicable):   ${summary.skipped}');

  final ordered = [
    ...summary.findings.where((f) => f.result?.color == RuleColor.red),
    ...summary.findings.where((f) => f.result?.color == RuleColor.amber),
    ...summary.findings.where((f) => f.needsInput),
    ...summary.findings.where((f) => f.skipped),
    ...summary.findings.where((f) => f.result?.color == RuleColor.green),
  ];

  final outJson = ordered
      .map((f) => {
            'pilot': f.pilotName,
            'pilotId': f.pilotId,
            'date': f.date,
            'check': f.kind.name,
            if (f.result != null) 'color': f.result!.color.name,
            if (f.result != null) 'clause': f.result!.clause,
            if (f.result != null) 'explanation': f.result!.explanation,
            if (f.needsInput) 'missingFields': f.missingFields,
            if (f.skipped) 'notApplicable': f.notApplicable,
          })
      .toList();

  File(outPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(outJson),
  );
  stdout.writeln('\nFull report written to $outPath');
}

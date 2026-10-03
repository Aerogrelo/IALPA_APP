import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/roster_day.dart';
import '../../services/roster_service.dart';

/// Button that lets the pilot pick a roster PDF from their device, sends
/// it to the roster-parsing cloud service (`roster_service/` at the repo
/// root), and hands back one chosen day's original report/finish time so
/// the caller can prefill its own fields with it.
///
/// Added 29/09 in response to Elena's UX critique of Change of Duty: "el
/// original report and finish time podria importarse del roster
/// directamente (dejando la opcion de hacerlo manual)". Deliberately
/// narrow in scope — it only ever proposes the day's ORIGINAL
/// (unchanged) report/finish time, since that's what's actually on the
/// roster; the pilot still enters the airline's proposed NEW time by
/// hand, and can edit whatever this fills in before verifying. Also used
/// on the Maximum Duty screen for the single report/end pair there.
///
/// A day the parser wasn't confident about (`needs_review`), a day off,
/// or an empty day is shown but disabled, with a note to enter it
/// manually — never guessed at (same principle the parser itself
/// follows server-side).
///
/// 30/09: the roster prints every time as local time at the station where
/// it happens, not UTC (confirmed with Elena/Guillermo) — the service now
/// converts each one to UTC itself (see `roster_service/roster_parser.py`
/// and [RosterDay]), so the times handed to [onImported] are always
/// correct UTC `DateTime`s, and the picker shows both LT and UTC so the
/// pilot can check it against their own roster at a glance.
///
/// 30/09 (later the same day): added the optional [onImportedDay]
/// callback, which — if provided — also hands back the full [RosterDay]
/// that was picked (station, Intercontinental/direction/time-difference
/// hints), so a caller like [MinRestInputScreen] can auto-detect which
/// rest scenario applies instead of asking the pilot to pick it. Existing
/// callers that don't need this (Maximum Duty, Change of Duty) are
/// unaffected — they only ever set [onImported].
class RosterImportButton extends StatefulWidget {
  const RosterImportButton({
    super.key,
    required this.onImported,
    this.onImportedDay,
  });

  /// Called with the chosen day's report and finish time (UTC).
  final void Function(DateTime report, DateTime finish) onImported;

  /// Called (in addition to [onImported]) with the full parsed day, for
  /// callers that want to auto-detect a scenario from it.
  final void Function(RosterDay day)? onImportedDay;

  @override
  State<RosterImportButton> createState() => _RosterImportButtonState();
}

class _RosterImportButtonState extends State<RosterImportButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _pickAndImport,
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.upload_file, size: 18),
        label: Text(_loading ? 'Reading roster…' : 'Import from roster (PDF)'),
      ),
    );
  }

  Future<void> _pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;

    setState(() => _loading = true);
    try {
      final initialYear = DateTime.now().toUtc().year;
      final days = await uploadRosterPdf(
        file.bytes!,
        file.name,
        year: initialYear,
      );
      if (!mounted) return;
      final picked =
          await showDialog<({DateTime report, DateTime finish, RosterDay day})>(
        context: context,
        builder: (_) => _RosterDayPickerDialog(
          bytes: file.bytes!,
          filename: file.name,
          initialDays: days,
          initialYear: initialYear,
        ),
      );
      if (picked != null) {
        widget.onImported(picked.report, picked.finish);
        widget.onImportedDay?.call(picked.day);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _RosterDayPickerDialog extends StatefulWidget {
  const _RosterDayPickerDialog({
    required this.bytes,
    required this.filename,
    required this.initialDays,
    required this.initialYear,
  });

  final Uint8List bytes;
  final String filename;
  final Map<String, dynamic> initialDays;
  final int initialYear;

  @override
  State<_RosterDayPickerDialog> createState() =>
      _RosterDayPickerDialogState();
}

class _RosterDayPickerDialogState extends State<_RosterDayPickerDialog> {
  // The roster PDF's day-grid header only ever prints day/month (e.g.
  // '02/07'), never a year — so we ask, defaulting to the current year.
  // Bumping it re-uploads: the service needs the year to convert local
  // station times to UTC correctly (the offset depends on the exact
  // date, because of DST), so a client-side-only year change would leave
  // the already-converted times silently wrong.
  late int _year = widget.initialYear;
  late Map<String, dynamic> _days = widget.initialDays;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final entries = _days.entries.toList()
      ..sort((a, b) => _dayMonthKey(a.key).compareTo(_dayMonthKey(b.key)));

    return AlertDialog(
      title: const Text('Which day?'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Year:'),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _loading ? null : () => _changeYear(_year - 1),
                ),
                Text('$_year'),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _loading ? null : () => _changeYear(_year + 1),
                ),
                if (_loading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const Text(
              'The roster doesn\'t print a year on this page — check it '
              'matches before picking a day.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children:
                    entries.map((e) => _buildRow(e.key, e.value)).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _changeYear(int newYear) async {
    setState(() => _loading = true);
    try {
      final days = await uploadRosterPdf(
        widget.bytes,
        widget.filename,
        year: newYear,
      );
      if (!mounted) return;
      setState(() {
        _year = newYear;
        _days = days;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildRow(String dateKey, dynamic dayJson) {
    final day = RosterDay.fromJson(dayJson as Map<String, dynamic>);
    final suggestion = day.suggestedTimes();

    final String subtitle;
    if (day.kind != null) {
      subtitle = day.kind == 'F' ? 'Day off' : day.kind!;
    } else if (day.status == 'empty') {
      subtitle = 'Nothing on the roster this day';
    } else if (suggestion == null) {
      subtitle = 'Could not read this day confidently — enter it manually';
    } else {
      final reportUtc = _hhmm(suggestion.report);
      final finishUtc = _hhmm(suggestion.finish);
      subtitle = 'Report ${suggestion.reportLt} LT ($reportUtc UTC) — '
          'Finish ${suggestion.finishLt} LT ($finishUtc UTC)';
    }

    return ListTile(
      dense: true,
      title: Text(dateKey),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      enabled: suggestion != null,
      onTap: suggestion == null
          ? null
          : () => Navigator.of(context).pop((
                report: suggestion.report,
                finish: suggestion.finish,
                day: day,
              )),
    );
  }

  String _hhmm(DateTime utc) =>
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')}';

  /// 03/10: a day with two duties printed in its cell (see
  /// roster_parser.py's `promote_second_duties`) comes back as a SECOND
  /// entry keyed "DD/MM (2)" right alongside the plain "DD/MM" one —
  /// strip that suffix before parsing the day/month, and use it as a
  /// tiebreaker so the second duty always sorts immediately after its
  /// own day. Same fix as `full_roster_audit_screen.dart`'s
  /// `_dayMonthKey` — this picker (used by Max Duty/Change of
  /// Duty/Minimum Rest) has its own copy and wasn't covered by that
  /// earlier fix, which is what threw `FormatException: 10 (2)` here.
  int _dayMonthKey(String key) {
    final isSecondDuty = key.endsWith(' (2)');
    final base = isSecondDuty ? key.substring(0, key.length - 4) : key;
    final parts = base.split('/');
    final day = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return month * 10000 + day * 100 + (isSecondDuty ? 1 : 0);
  }
}

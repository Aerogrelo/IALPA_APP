import 'package:flutter/material.dart';

/// A label + "Change" button that opens a date and time picker and stores
/// the result as UTC, with no implicit conversion from the device's local
/// time zone. Shared by every duty-entry screen (Maximum Duty, Change of
/// Duty, and future ones) — extracted 29/09 from [MaxDutyInputScreen]'s
/// original private copy so it isn't duplicated per screen.
///
/// **Time zone:** pilots think in Zulu time for duty hours, and the
/// convenio's own report/end time bands are meant to be read that way
/// too. The date and time pickers only ever hand back the raw wall-clock
/// digits the person chose; [_pick] rebuilds the result with
/// [DateTime.utc] (never the plain [DateTime] constructor) so those
/// digits are stored exactly as given, with no local-time conversion.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label\n${_format(value)}',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        TextButton(
          onPressed: () => _pick(context),
          child: const Text('Change'),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime.utc(value.year - 1),
      lastDate: DateTime.utc(value.year + 1),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
    );
    if (time == null) return;

    onChanged(
      DateTime.utc(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  String _format(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} '
        '${two(d.hour)}:${two(d.minute)} UTC';
  }
}

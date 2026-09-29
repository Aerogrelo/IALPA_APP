enum DutyType { flight, stba, stbh, k }

enum TransatlanticDirection { none, eastbound, westbound }

class Duty {
  final DateTime report;
  final DateTime end;
  final DutyType type;
  final int sectors;
  final bool deadheading;
  final TransatlanticDirection transatlanticDirection;
  final Duration timeDifference;

  const Duty({
    required this.report,
    required this.end,
    required this.type,
    this.sectors = 1,
    this.deadheading = false,
    this.transatlanticDirection = TransatlanticDirection.none,
    this.timeDifference = Duration.zero,
  });

  Duration get duration => end.difference(report);

  /// Whether this duty encompasses 0330 local, per clause 3.18 of the
  /// A320/321 Working Conditions (used for through-the-night limitations).
  bool get isThroughTheNight {
    var reference0330 = DateTime(report.year, report.month, report.day, 3, 30);
    if (reference0330.isBefore(report)) {
      reference0330 = reference0330.add(const Duration(days: 1));
    }
    return !reference0330.isBefore(report) && reference0330.isBefore(end);
  }
}

/// A single day's parsed roster entry, as returned by the roster-parsing
/// cloud service (`roster_service/` at the repo root — a small FastAPI
/// service, deployed separately on Render, not part of this app's build).
/// See `roster_service/README.md` for the full JSON shape this mirrors.
///
/// 30/09: the roster PDF prints every time as LOCAL TIME AT THE STATION
/// where it happens (confirmed with Elena/Guillermo) — not UTC. The app's
/// rule engine works only in UTC (IALPA/EASA duty limits are defined that
/// way), so the service now converts every time to UTC itself, station by
/// station, and sends both: the original `HH:MM` local fields (kept, for
/// display — a pilot recognises their own roster's local times) and a
/// parallel set of `...Utc` fields (ISO 8601). This model reads the UTC
/// fields for anything that will feed the rule engine, and keeps the LT
/// strings only for showing the pilot what they'd expect to see.
class RosterDay {
  RosterDay({
    required this.status,
    this.kind,
    this.reportTime,
    this.trailingTime,
    this.reportTimeUtc,
    this.trailingTimeUtc,
    required this.legs,
    required this.standbys,
    required this.flags,
  });

  factory RosterDay.fromJson(Map<String, dynamic> json) {
    return RosterDay(
      status: json['status'] as String? ?? 'needs_review',
      kind: json['kind'] as String?,
      reportTime: json['reportTime'] as String?,
      trailingTime: json['trailingTime'] as String?,
      reportTimeUtc: _parseUtc(json['reportTimeUtc']),
      trailingTimeUtc: _parseUtc(json['trailingTimeUtc']),
      legs: (json['legs'] as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[],
      standbys: (json['standbys'] as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[],
      flags: (json['flags'] as List?)?.cast<String>() ?? const <String>[],
    );
  }

  final String status; // 'ok' | 'needs_review' | 'empty'
  final String? kind; // 'F' | 'GL' for a day off
  final String? reportTime; // 'HH:MM', local to the report station
  final String? trailingTime; // 'HH:MM', local to the finish station
  final DateTime? reportTimeUtc;
  final DateTime? trailingTimeUtc;
  final List<Map<String, dynamic>> legs;
  final List<Map<String, dynamic>> standbys;
  final List<String> flags;

  static DateTime? _parseUtc(dynamic value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static DateTime? _legTimeUtc(Map<String, dynamic> leg, String key) {
    final value = leg['${key}Utc'];
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }

  /// Best-guess (report, finish) UTC pair to prefill the ORIGINAL
  /// report/finish time fields with — or null when this day isn't a
  /// single clear duty period the parser is confident about (a day off,
  /// an empty day, or one flagged `needs_review`), or when the service
  /// couldn't resolve a station's timezone for one of the needed times.
  /// Deliberately returns null rather than a guess in those cases — the
  /// pilot enters it by hand instead, same "flag for review, never
  /// guess" principle the parser itself follows.
  ///
  /// Also returns the same pair's local-time strings (`reportLt`,
  /// `finishLt`) purely for display, so the picker can show the pilot
  /// both ("14:25 LT (13:25 UTC)") and they can sanity-check it against
  /// their own roster at a glance.
  ({DateTime report, DateTime finish, String reportLt, String finishLt})?
      suggestedTimes() {
    if (status != 'ok' || kind != null) return null;

    var report = reportTimeUtc;
    var finish = trailingTimeUtc;
    var reportLt = reportTime;
    var finishLt = trailingTime;

    if (legs.isNotEmpty) {
      if (report == null) {
        report = _legTimeUtc(legs.first, 'offBlock');
        reportLt = legs.first['offBlock'] as String?;
      }
      if (finish == null) {
        finish = _legTimeUtc(legs.last, 'onBlock');
        finishLt = legs.last['onBlock'] as String?;
      }
    }
    if (standbys.isNotEmpty) {
      if (report == null) {
        report = _legTimeUtc(standbys.first, 'start');
        reportLt = standbys.first['start'] as String?;
      }
      if (finish == null) {
        finish = _legTimeUtc(standbys.last, 'end');
        finishLt = standbys.last['end'] as String?;
      }
    }

    if (report == null || finish == null || reportLt == null || finishLt == null) {
      return null;
    }
    return (report: report, finish: finish, reportLt: reportLt, finishLt: finishLt);
  }
}

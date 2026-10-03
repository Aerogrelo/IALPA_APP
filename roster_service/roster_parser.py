"""Core roster-PDF parsing logic.

Ported unchanged from the prototype validated against two real Aer Lingus
rosters (30/09): 30/31 'ok' + 1/31 correctly-'empty' on the July roster,
31/31 'ok' on the August roster.

Extended here to loop over every page of the PDF (the prototype only
looked at page 0), so a roster PDF spanning more than one month is fully
parsed. Each page is expected to carry its own date-column header row.

30/09 (this session): two further passes added after the raw per-page
extraction, both needed because Elena confirmed the printed times are
LOCAL TIME AT EACH STATION, not UTC — the app's rule engine works only in
UTC (IALPA/EASA duty limits are defined that way), so raw HH:MM values are
not directly usable:

1. `resolve_utc_times` — walks the roster in chronological order, tracking
   which station the pilot is physically at (a report after an overnight
   away is local to wherever they are, per Elena), and converts every
   printed HH:MM to a full UTC datetime using each leg's actual
   origin/destination airport timezone (`airportsdata` + `zoneinfo`,
   correctly handling DST for the given year). Adds `...Utc` fields
   alongside the original LT ones (`reportTimeUtc`, `trailingTimeUtc`,
   `offBlockUtc`, `onBlockUtc`, standby `startUtc`/`endUtc`) rather than
   replacing them, so the app can show both ("14:25 LT (13:25 UTC)").
2. `stitch_overnight_duties` — for a duty that the roster prints across
   two day-rows (a 'continues_next_day' flight with no arrival time, whose
   arrival appears on the next day's 'continuation_from_previous_day'
   row), copies the missing half across so BOTH rows carry a complete
   report+finish pair for the SAME duty, instead of each being
   individually incomplete and unimportable.

Both passes are best-effort: known simplifications are noted inline, and
anything that can't be resolved confidently is left as-is rather than
guessed (same principle as the token parser below).

30/09 (later the same day): a third pass, `annotate_scenario_hints`, adds
per-day fields the app uses to AUTO-DETECT which Minimum Rest scenario
applies (base/outstation, continental/intercontinental, direction, time
difference) instead of making the pilot pick it from a list every time —
Elena's request, to cut down on manual selection now that the roster
already carries this information. These are hints, not verdicts: the app
still shows what was detected and lets the pilot correct it before
verifying, same "never silently guess" principle as everything else here.

03/10: a fourth pass, `promote_second_duties`, handles a real print shape
found in Guillermo's own August roster that none of the above anticipated
— a day whose cell packs TWO entirely separate duties: the tail end of an
overnight duty finishing in the early hours, immediately followed by a
brand-new same-day duty's own report/legs/finish. `parse_day` now detects
and splits this (see `_split_duties`) instead of silently merging the two
into one (which used to lose the first duty's true finish time and made
the app ask for a "finish time" that was in fact printed on the PDF all
along). `resolve_utc_times` runs its station-tracking/UTC-conversion
logic a second time for the split-off second duty (via `_process_duty`),
and `promote_second_duties` lifts it into its own top-level day entry
("07/08 (2)") once both earlier passes are done, so the rest of the
pipeline — and the Dart app, which just trusts whatever order the `days`
map comes in — see two ordinary, complete days instead of one merged one.
"""

import re
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

FLIGHT_COLOR = (0.039216, 0.43137, 0.74118)  # blue — flight numbers
DELAY_COLOR = (0.50196, 0.0, 0.0)  # red — Delay

TIME_RE = re.compile(r"^\d{2}:\d{2}$")
ACTUAL_TIME_RE = re.compile(r"^A(\d{2}:\d{2})$")
STATION_RE = re.compile(r"^[A-Z]{3}$")
AIRCRAFT_RE = re.compile(r"^\[[0-9A-Z]+\]$")
DAY_OFF_CODES = {"F", "GL"}
STANDBY_CODES = {"STBH", "STBQ"}
BRIEFING_CODES = {"BR"}  # briefing after a long gap not flying to a station; counts as duty
DUTY_BLOCK_CODES = STANDBY_CODES | BRIEFING_CODES

HOME_BASE = "DUB"

# Countries Aer Lingus's Intercontinental (transatlantic) network reaches.
# Everything else the airline flies to is Continental in the sense the
# Working Conditions use the word. A small, explicit set rather than a
# general continent library, because this airline's actual route network
# only crosses into "Intercontinental" for North America — if that ever
# changes (a new long-haul destination), this is the one place to update.
INTERCONTINENTAL_COUNTRIES = {"US", "CA"}


def close(c1, c2, tol=0.02):
    if c1 is None:
        return False
    return all(abs(a - b) < tol for a, b in zip(c1, c2))


DATE_HEADER_RE = re.compile(r"^\d{1,2}/\d{1,2}$")


def parse_page(page):
    words = page.extract_words(extra_attrs=["non_stroking_color"])
    header = [w for w in words if 100 <= w["top"] <= 106 and DATE_HEADER_RE.match(w["text"])]
    header.sort(key=lambda w: w["x0"])
    col_dates = [w["text"] for w in header]
    col_x = [w["x0"] for w in header]

    # A roster grid page has one header cell per day of the month (28-31).
    # Other pages (legend, totals, memos, hotel info) sometimes have a
    # stray word matching '/' in that same vertical band but never this
    # many — skip anything that isn't a real day-grid header row.
    if len(col_dates) < 20:
        return {}

    def col_index(x0):
        best_i, best_d = None, 1e9
        for i, cx in enumerate(col_x):
            d = abs(x0 - cx)
            if d < best_d:
                best_d, best_i = d, i
        return best_i

    grid_words = [w for w in words if 106 < w["top"] < 400]
    days = defaultdict(list)
    for w in grid_words:
        days[col_index(w["x0"])].append(w)

    weekday_names = {"Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue"}
    results = {}
    for i, date_str in enumerate(col_dates):
        ws = sorted(days.get(i, []), key=lambda w: w["top"])
        tokens = [
            (w["text"].strip().strip("​"), w.get("non_stroking_color"))
            for w in ws
            if w["text"].strip().strip("​") not in weekday_names
            and w["text"].strip().strip("​") != ""
        ]
        results[date_str] = parse_day(tokens)
    return results


def parse_day(tokens):
    if not tokens:
        return {"status": "empty"}

    texts = [t for t, c in tokens]
    if texts[0] in DAY_OFF_CODES:
        return {"status": "ok", "kind": texts[0]}

    # flags carries (token_index, text) pairs rather than plain strings —
    # needed (03/10) to tell which half a flag belongs to once a day
    # turns out to hold two duties (see below): a flag recorded AFTER the
    # split point (e.g. "continues_next_day" from a token near the end of
    # the cell) describes the SECOND duty, not the first.
    flags = []
    i = 0
    n = len(tokens)
    continuation = False
    if texts[0] == "↓":
        continuation = True
        i = 1
        flags.append((0, "continuation_from_previous_day"))

    # 03/10: tokens are collected into an ordered list of events (a leg, a
    # standby, or a bare time, each tagged with its token index) instead
    # of writing straight into report_time/trailing_time/legs/standbys as
    # they're seen. The token shapes below (flight legs, standbys, the
    # Delay annotation, the overnight-continuation leg) are unchanged
    # from before -- this is only a different way of GROUPING the same
    # events afterwards, so a day with exactly one duty (the overwhelming
    # majority) ends up with the identical result as before. It's what
    # lets _split_duties() (below) recognise the one real exception: a
    # roster cell that packs TWO separate duties into the same calendar
    # day (confirmed 03/10 against Guillermo's real August roster, days
    # 06-07/08 and 22-23/08 both: the tail end of an overnight duty
    # finishing early morning, immediately followed by a brand-new
    # same-day duty's own report, legs and finish -- e.g. "...arrival
    # leg, 02:35, 15:20, <new legs>, 22:59"). Before this, the second bare
    # time silently overwrote the first, so the true overnight-duty
    # finish time was lost and the day looked like it needed a
    # manually-entered finish time it had never actually been missing.
    events = []
    delays = []

    def has_content():
        return any(kind in ("leg", "standby") for kind, _, _ in events)

    while i < n:
        text, color = tokens[i]

        if text == "→":
            flags.append((i, "continues_next_day"))
            i += 1
            continue

        if text == "M":
            i += 1
            continue

        if text in DUTY_BLOCK_CODES:
            if i + 2 < n and TIME_RE.match(tokens[i + 1][0]) and TIME_RE.match(tokens[i + 2][0]):
                events.append(
                    ("standby", {"code": text, "start": tokens[i + 1][0], "end": tokens[i + 2][0]}, i)
                )
                i += 3
                continue
            else:
                flags.append((i, f"unrecognised_standby_shape_at_{i}"))
                i += 1
                continue

        if close(color, DELAY_COLOR) and text == "Delay":
            if i + 1 < n and TIME_RE.match(tokens[i + 1][0]):
                delays.append(tokens[i + 1][0])
                i += 2
                continue
            else:
                flags.append((i, f"unrecognised_delay_shape_at_{i}"))
                i += 1
                continue

        if close(color, FLIGHT_COLOR):

            def block_time(tok):
                m = ACTUAL_TIME_RE.match(tok)
                if m:
                    return m.group(1), True
                if TIME_RE.match(tok):
                    return tok, False
                return None, None

            off_val, off_actual = block_time(tokens[i + 1][0]) if i + 1 < n else (None, None)
            on_val, on_actual = block_time(tokens[i + 4][0]) if i + 4 < n else (None, None)
            if (
                i + 5 < n
                and off_val is not None
                and STATION_RE.match(tokens[i + 2][0])
                and STATION_RE.match(tokens[i + 3][0])
                and on_val is not None
                and AIRCRAFT_RE.match(tokens[i + 5][0])
            ):
                events.append(
                    (
                        "leg",
                        {
                            "flightNumber": text,
                            "offBlock": off_val,
                            "offBlockActual": off_actual,
                            "origin": tokens[i + 2][0],
                            "destination": tokens[i + 3][0],
                            "onBlock": on_val,
                            "onBlockActual": on_actual,
                            "aircraft": tokens[i + 5][0].strip("[]"),
                        },
                        i,
                    )
                )
                i += 6
                continue
            off2_val, off2_actual = block_time(tokens[i + 1][0]) if i + 1 < n else (None, None)
            if off2_val is not None and i + 2 < n and STATION_RE.match(tokens[i + 2][0]) and (
                i + 3 >= n or tokens[i + 3][0] == "→"
            ):
                events.append(
                    (
                        "leg",
                        {
                            "flightNumber": text,
                            "offBlock": off2_val,
                            "offBlockActual": off2_actual,
                            "origin": None,
                            "destination": tokens[i + 2][0],
                            "onBlock": None,
                            "onBlockActual": None,
                            "aircraft": None,
                            "continuesNextDay": True,
                        },
                        i,
                    )
                )
                i += 3
                continue
            else:
                flags.append((i, f"unrecognised_flight_shape_at_{i}"))
                i += 1
                continue

        if continuation and not has_content() and STATION_RE.match(text):
            if i + 2 < n and ACTUAL_TIME_RE.match(tokens[i + 1][0]) and AIRCRAFT_RE.match(tokens[i + 2][0]):
                events.append(
                    (
                        "leg",
                        {
                            "flightNumber": None,
                            "offBlock": None,
                            "origin": None,
                            "destination": text,
                            "onBlock": ACTUAL_TIME_RE.match(tokens[i + 1][0]).group(1),
                            "aircraft": tokens[i + 2][0].strip("[]"),
                            "continuedFromPreviousDay": True,
                        },
                        i,
                    )
                )
                i += 3
                continue

        if TIME_RE.match(text):
            events.append(("time", text, i))
            i += 1
            continue

        flags.append((i, f"unclassified_token:{text!r}_at_{i}"))
        i += 1

    split = _split_duties(events)
    second_duty = split["secondDuty"]
    extra_flags1 = split["extra_flags1"]
    extra_flags2 = split["extra_flags2"]
    split_token_idx = split["split_token_idx"]

    # Partition the flat (token_idx, text) flags by which duty they
    # describe. Without a split everything is duty 1's, same as before
    # 03/10. With a split, anything recorded at or before the split
    # point (duty 1's closing bare time) is duty 1's; anything after —
    # notably a trailing "continues_next_day" from a token near the end
    # of the cell — is duty 2's, even though the walk above only ever
    # wrote to one shared `flags` list.
    if split_token_idx is None:
        flags1 = [text for _, text in flags]
        flags2 = []
    else:
        flags1 = [text for idx, text in flags if idx <= split_token_idx]
        flags2 = [text for idx, text in flags if idx > split_token_idx]

    def _problem(fs):
        return any(f.startswith("unrecognised") or f.startswith("unclassified") for f in fs)

    if second_duty is not None:
        flags1.append("second_duty_same_day")
        second_duty["flags"] = flags2 + extra_flags2
        second_duty["delays"] = []
        second_duty["status"] = "needs_review" if (_problem(flags2) or extra_flags2) else "ok"

    out = {
        "status": "needs_review" if (_problem(flags1) or extra_flags1) else "ok",
        "reportTime": split["reportTime"],
        "standbys": split["standbys"],
        "legs": split["legs"],
        "delays": delays,
        "trailingTime": split["trailingTime"],
        "flags": flags1 + extra_flags1,
    }
    if second_duty is not None:
        out["secondDuty"] = second_duty
    return out


def _split_duties(events):
    """Group a day's ordered (leg/standby/time) events — each a
    (kind, payload, token_index) triple — into one duty, or, when the
    cell packs two entirely separate duties into the same calendar day,
    into two (see the note in parse_day above for the real shape this
    handles). The tell: two bare 'time' events back to back, with at
    least one leg or standby already seen before them. The first of the
    pair closes out the duty already in progress (its true finish time,
    which used to get silently overwritten); the second opens a
    brand-new duty that continues to the end of the token stream.

    When the pattern doesn't appear — the normal case — this returns
    exactly what the old inline code did: one report time (the first bare
    time seen before any leg/standby), one trailing time (the last bare
    time after), and the legs/standbys in between.
    """

    def _gather(evs):
        report_time = None
        trailing_time = None
        legs = []
        standbys = []
        extra = []
        for kind, payload, _idx in evs:
            if kind == "leg":
                legs.append(payload)
            elif kind == "standby":
                standbys.append(payload)
            elif kind == "time":
                if report_time is None and not legs and not standbys:
                    report_time = payload
                elif trailing_time is None:
                    trailing_time = payload
                else:
                    # More bare times than one duty should ever have.
                    # Keep the latest (closest to the pre-03/10 behaviour)
                    # but flag it so it gets a manual look instead of
                    # being silently trusted.
                    extra.append("extra_bare_time_ignored")
                    trailing_time = payload
        return report_time, trailing_time, legs, standbys, extra

    split_at = None
    seen_content = False
    for idx, (kind, _payload, _tok_idx) in enumerate(events):
        if kind in ("leg", "standby"):
            seen_content = True
            continue
        if kind == "time" and seen_content and idx + 1 < len(events) and events[idx + 1][0] == "time":
            split_at = idx
            break

    if split_at is None:
        report_time, trailing_time, legs, standbys, extra = _gather(events)
        return {
            "reportTime": report_time,
            "trailingTime": trailing_time,
            "legs": legs,
            "standbys": standbys,
            "secondDuty": None,
            "extra_flags1": extra,
            "extra_flags2": [],
            "split_token_idx": None,
        }

    split_token_idx = events[split_at][2]
    finish_time = events[split_at][1]
    second_report = events[split_at + 1][1]
    report_time, _, legs, standbys, extra1 = _gather(events[:split_at])
    _, second_trailing, second_legs, second_standbys, extra2 = _gather(
        [("time", second_report, events[split_at + 1][2])] + events[split_at + 2 :]
    )

    return {
        "reportTime": report_time,
        "trailingTime": finish_time,
        "legs": legs,
        "standbys": standbys,
        "secondDuty": {
            "reportTime": second_report,
            "trailingTime": second_trailing,
            "legs": second_legs,
            "standbys": second_standbys,
        },
        "extra_flags1": extra1,
        "extra_flags2": extra2,
        "split_token_idx": split_token_idx,
    }


# ---------------------------------------------------------------------------
# LT -> UTC conversion (30/09) — added because roster times print local
# time at each station, but the app's rule engine works only in UTC.
# ---------------------------------------------------------------------------

_AIRPORT_TZ_CACHE = None


def _airport(code):
    """Return the airportsdata record for an IATA station code, or None."""
    global _AIRPORT_TZ_CACHE
    if not code or not STATION_RE.match(code):
        return None
    if _AIRPORT_TZ_CACHE is None:
        import airportsdata

        _AIRPORT_TZ_CACHE = airportsdata.load("IATA")
    return _AIRPORT_TZ_CACHE.get(code)


def _station_tz(code):
    """Return the zoneinfo.ZoneInfo for an IATA station code, or None if
    unknown (airportsdata doesn't have it, or code is missing/malformed)."""
    airport = _airport(code)
    if not airport or not airport.get("tz"):
        return None
    from zoneinfo import ZoneInfo

    return ZoneInfo(airport["tz"])


def _station_country(code):
    airport = _airport(code)
    return airport.get("country") if airport else None


def _is_intercontinental_station(code):
    return _station_country(code) in INTERCONTINENTAL_COUNTRIES


def _to_utc(local_date, hhmm, station_code):
    """Convert an HH:MM string, local to `station_code` on `local_date`,
    to a UTC datetime. Returns None if the station's timezone is unknown
    or hhmm doesn't parse — callers should not fail on that, just skip the
    ...Utc field for that value."""
    tz = _station_tz(station_code)
    if tz is None or not hhmm or not TIME_RE.match(hhmm):
        return None
    hour, minute = (int(p) for p in hhmm.split(":"))
    local_dt = datetime(local_date.year, local_date.month, local_date.day, hour, minute, tzinfo=tz)
    return local_dt.astimezone(timezone.utc)


def _day_sort_key(date_str, year):
    day, month = (int(p) for p in date_str.split("/"))
    # Rosters are usually a single month or span a month boundary forward
    # (e.g. 28/06..05/07) — assume the year given applies to every date;
    # cross-year rosters (Dec->Jan) aren't handled here, a known gap.
    return (year, month, day)


def _process_duty(duty, local_date, start_station):
    """Convert one duty's LT fields to UTC in place, tracking which
    station the pilot moves to leg by leg — the one piece of
    resolve_utc_times' station-tracking/UTC-conversion logic, factored
    out (03/10) so it can run a second time, unchanged, for a same-day
    second duty (see parse_day/_split_duties) exactly as it already runs
    for the day's (only, or first) duty. `duty` is either the day's own
    dict or its `secondDuty` sub-dict — both use the same field names
    (reportTime/legs/standbys/trailingTime).

    Returns (end_station, intercontinental, transatlantic_direction,
    time_difference_hours) for the caller to store on whichever dict
    `duty` was, and to chain into the next call (next day, or this same
    day's second duty) as its `start_station`.
    """
    current_station = start_station
    intercontinental = False
    direction = None
    time_diff_hours = None

    report_time = duty.get("reportTime")
    if report_time:
        report_utc = _to_utc(local_date, report_time, start_station)
        if report_utc:
            duty["reportTimeUtc"] = report_utc.isoformat()

    for leg in duty.get("legs", []):
        if leg.get("continuedFromPreviousDay"):
            on_utc = _to_utc(local_date, leg.get("onBlock"), leg.get("destination"))
            if on_utc:
                leg["onBlockUtc"] = on_utc.isoformat()
            if leg.get("destination"):
                current_station = leg["destination"]
            continue

        origin = leg.get("origin") or current_station
        off_utc = _to_utc(local_date, leg.get("offBlock"), origin)
        if off_utc:
            leg["offBlockUtc"] = off_utc.isoformat()

        destination = leg.get("destination")
        if leg.get("onBlock") and destination:
            on_utc = _to_utc(local_date, leg["onBlock"], destination)
            # A sector never takes >20h on this fleet — if the naive
            # same-date conversion lands before departure (or absurdly
            # close after it, implying it actually landed the next
            # calendar day at destination), roll the local arrival
            # date forward by one day and reconvert.
            if on_utc and off_utc and on_utc <= off_utc:
                on_utc = _to_utc(local_date + timedelta(days=1), leg["onBlock"], destination)
            if on_utc:
                leg["onBlockUtc"] = on_utc.isoformat()

        # Intercontinental / direction / time-difference hint for this
        # leg — only meaningful once we have both ends' UTC times.
        if _is_intercontinental_station(origin) or _is_intercontinental_station(destination):
            intercontinental = True
            off_tz = _station_tz(origin)
            on_tz = _station_tz(destination)
            on_utc_val = leg.get("onBlockUtc")
            if off_tz and off_utc and on_tz and on_utc_val:
                on_dt = datetime.fromisoformat(on_utc_val)
                off_local_offset = off_utc.astimezone(off_tz).utcoffset()
                on_local_offset = on_dt.astimezone(on_tz).utcoffset()
                if off_local_offset is not None and on_local_offset is not None:
                    diff_hours = abs((off_local_offset - on_local_offset).total_seconds()) / 3600
                    time_diff_hours = round(diff_hours)
            if _is_intercontinental_station(destination) and not _is_intercontinental_station(origin):
                direction = "westbound"
            elif _is_intercontinental_station(origin) and not _is_intercontinental_station(destination):
                direction = "eastbound"

        if destination:
            current_station = destination

    # Catch-all (30/09): the per-leg check above only fires for a
    # "regular" leg — an overnight leg that continues onto the next day's
    # row (the 'continuedFromPreviousDay' branch) returns early and skips
    # it. Rather than special-case every token shape, this checks the
    # duty's overall start/end station instead: if the pilot started or
    # ended it at an Intercontinental station, it counts as
    # Intercontinental regardless of which branch parsed its legs.
    if _is_intercontinental_station(start_station) or _is_intercontinental_station(current_station):
        intercontinental = True

    for standby in duty.get("standbys", []):
        start_utc = _to_utc(local_date, standby.get("start"), start_station)
        if start_utc:
            standby["startUtc"] = start_utc.isoformat()
        end_utc = _to_utc(local_date, standby.get("end"), start_station)
        if end_utc and start_utc and end_utc <= start_utc:
            end_utc = _to_utc(local_date + timedelta(days=1), standby.get("end"), start_station)
        if end_utc:
            standby["endUtc"] = end_utc.isoformat()

    trailing_time = duty.get("trailingTime")
    if trailing_time:
        trailing_utc = _to_utc(local_date, trailing_time, current_station)
        if trailing_utc:
            duty["trailingTimeUtc"] = trailing_utc.isoformat()

    return current_station, intercontinental, direction, time_diff_hours


def resolve_utc_times(all_results, year, home_base=HOME_BASE):
    """Walk the roster chronologically, tracking which station the pilot
    is physically at, and add '...Utc' fields (ISO 8601, UTC) alongside
    every existing LT field, without removing or changing the LT ones.

    Also records, per day (30/09, later the same day): `reportStation` —
    where the pilot physically is at the start of the day's duty/standby
    — and `finishStation` — where they end up by the end of it. These
    feed the app's scenario auto-detection (base vs outstation): a day
    that starts AND ends at `home_base` is "at base"; one that ends
    somewhere else is "at an outstation" (matching how 3.14.1(a)/(b) of
    the A320/321 Working Conditions, and the equivalent A330 clause 3.13,
    define those terms).

    03/10: when parse_day found a same-day second duty (`secondDuty` —
    see parse_day/_split_duties), it gets the exact same treatment via
    _process_duty, continuing from wherever the day's first duty left the
    pilot — so a day with two duties ends up with two complete, correctly
    station-tracked and UTC-converted records instead of one merged,
    partly-wrong one. Each duty's own reportStation/finishStation/
    intercontinental/etc. are self-contained (the hint fields describe
    THAT duty, not the whole day) — this matters once promote_second_duties
    (below) lifts `secondDuty` into its own day-shaped entry.

    Simplifications, flagged here rather than hidden in the code:
    - After a day off ('F'/'GL'), the pilot is assumed to be back at
      `home_base` for whatever comes next — the roster doesn't say where
      a pilot spends a day off, but for a Dublin-based pilot this is the
      overwhelmingly common case.
    - A leg without an explicit origin (the two token shapes that don't
      carry one — a same-day departure continuing into the next day, or
      an arrival continuing from the previous day) is assumed to depart
      from wherever the pilot currently is, per the running station
      tracker — this is exactly what "origin" means for those shapes.
    - report/trailing times that aren't tied to a specific leg (e.g. a
      report before the day's first leg, standby start/end) are localised
      to the tracked "station at that point in the day" and are not
      themselves allowed to roll the calendar date forward/back — only
      leg off/on-block times are (see below). A report or finish very
      close to local midnight is the one case this could misdate; no
      case like that has been seen in Guillermo's real rosters so far.
    """
    ordered_keys = sorted(
        (k for k in all_results if DATE_HEADER_RE.match(k)),
        key=lambda k: _day_sort_key(k, year),
    )

    current_station = home_base
    for key in ordered_keys:
        entry = all_results[key]
        if entry.get("status") not in ("ok", "needs_review"):
            continue
        if entry.get("kind") in DAY_OFF_CODES:
            current_station = home_base
            continue

        day, month = (int(p) for p in key.split("/"))
        local_date = date(year, month, day)
        station_at_start = current_station
        entry["reportStation"] = station_at_start

        end_station, intercontinental, direction, time_diff = _process_duty(
            entry, local_date, station_at_start
        )
        entry["finishStation"] = end_station
        entry["intercontinental"] = intercontinental
        if direction:
            entry["transatlanticDirection"] = direction
        if time_diff is not None:
            entry["intercontinentalTimeDifferenceHours"] = time_diff

        second = entry.get("secondDuty")
        if second:
            second["reportStation"] = end_station
            end_station2, intercontinental2, direction2, time_diff2 = _process_duty(
                second, local_date, end_station
            )
            second["finishStation"] = end_station2
            second["intercontinental"] = intercontinental2
            if direction2:
                second["transatlanticDirection"] = direction2
            if time_diff2 is not None:
                second["intercontinentalTimeDifferenceHours"] = time_diff2
            current_station = end_station2
        else:
            current_station = end_station

    return all_results


# ---------------------------------------------------------------------------
# Overnight-duty stitching (30/09) — a duty the roster prints across two
# day-rows (report on day N, arrival shown on day N+1) is completed on
# BOTH rows so either one gives the app a full report+finish pair for the
# same duty, instead of each being individually incomplete.
# ---------------------------------------------------------------------------


def stitch_overnight_duties(all_results, year):
    ordered_keys = sorted(
        (k for k in all_results if DATE_HEADER_RE.match(k)),
        key=lambda k: _day_sort_key(k, year),
    )

    for idx, key in enumerate(ordered_keys):
        entry = all_results[key]
        # 03/10: the duty that can actually run into the next day is
        # whichever one ENDS this calendar day — the same-day second
        # duty when parse_day found one (see _split_duties), otherwise
        # the day's only duty. The "continues_next_day" flag for that
        # trailing duty lives on its own flags list (parse_day assigns
        # each flag to whichever duty it actually describes), never on
        # the day's primary duty once a split has happened — the one
        # case that matters here is a day whose SECOND duty is itself
        # an overnight one (e.g. 23/08's new 17:30 duty flying on into
        # 24/08) — stitching must continue from that, not from the
        # primary duty that already finished hours earlier.
        last_duty = entry.get("secondDuty") or entry
        if "continues_next_day" not in last_duty.get("flags", []):
            continue
        if idx + 1 >= len(ordered_keys):
            continue
        next_entry = all_results[ordered_keys[idx + 1]]
        # Only the next day's FIRST duty can be the continuation — the
        # '↓' marker that creates it is always the very first token of
        # the day, so it's never the next day's own secondDuty.
        if "continuation_from_previous_day" not in next_entry.get("flags", []):
            continue

        # Prefer the next day's own (first) duty trailing time when
        # parse_day already resolved it directly — e.g. the "Delay + two
        # bare times" shape that splits into a same-day second duty: the
        # bare time right after the arrival leg IS the overnight duty's
        # true finish, no digging into `legs` needed. Fall back to the
        # narrower continuedFromPreviousDay-tagged-leg lookup for the
        # other print shape, where the arrival is a bare 3-token leg
        # with no separate bare finish time printed alongside it.
        finish_time = next_entry.get("trailingTime")
        finish_time_utc = next_entry.get("trailingTimeUtc")
        if not finish_time_utc:
            arrival_leg = next(
                (l for l in next_entry.get("legs", []) if l.get("continuedFromPreviousDay")),
                None,
            )
            if arrival_leg and "onBlockUtc" in arrival_leg:
                finish_time = arrival_leg.get("onBlock")
                finish_time_utc = arrival_leg["onBlockUtc"]

        if not finish_time_utc:
            continue

        # Fill this duty's missing finish with the continuation's
        # arrival, and the continuation day's missing report with this
        # duty's original report — so both rows describe the same
        # complete duty.
        if not last_duty.get("trailingTimeUtc"):
            last_duty["trailingTime"] = finish_time
            last_duty["trailingTimeUtc"] = finish_time_utc
            last_duty.setdefault("flags", []).append("finish_time_from_next_day")
        if not next_entry.get("reportTimeUtc") and last_duty.get("reportTimeUtc"):
            next_entry["reportTime"] = last_duty.get("reportTime")
            next_entry["reportTimeUtc"] = last_duty["reportTimeUtc"]
            next_entry.setdefault("flags", []).append("report_time_from_previous_day")

    return all_results


# ---------------------------------------------------------------------------
# Same-day second-duty promotion (03/10) — lifts a day's `secondDuty` (see
# parse_day/_split_duties) into its own top-level entry, so the app's
# existing per-day model and batch audits — which already just trust
# whatever order the `days` map is in (lib/models/roster_day.dart,
# lib/batch/master_roster_audit.dart) — see two separate, complete duty
# records for that calendar date with zero changes needed on that side.
# ---------------------------------------------------------------------------


def _second_duty_key(date_str):
    return f"{date_str} (2)"


def promote_second_duties(all_results, year):
    """Must run AFTER resolve_utc_times/stitch_overnight_duties: the
    synthetic "dd/mm (2)" key doesn't match DATE_HEADER_RE and would
    otherwise be silently skipped by both passes' own chronological
    walks (which is exactly why this runs last, once every field both
    passes fill in is already in place).

    Rebuilds `all_results` in calendar order so each promoted entry lands
    immediately after its own day and before the next calendar day —
    dict insertion order is what the JSON response (and the Dart side
    reading it) preserves.
    """
    ordered_keys = sorted(
        (k for k in all_results if DATE_HEADER_RE.match(k)),
        key=lambda k: _day_sort_key(k, year),
    )

    rebuilt = {}
    for key in ordered_keys:
        entry = all_results[key]
        second = entry.pop("secondDuty", None)
        rebuilt[key] = entry
        if second is None:
            continue
        second.setdefault("status", "ok")
        second.setdefault("flags", [])
        second.setdefault("delays", [])
        second_key = _second_duty_key(key)
        rebuilt[second_key] = second
        entry.setdefault("flags", []).append(f"second_duty_promoted_to:{second_key}")

    # Carry over anything that wasn't a date-header key unchanged (there
    # shouldn't be any in practice — parse_page only ever keys by the
    # header row's own date strings — but this keeps the function safe
    # if that ever changes).
    for key, entry in all_results.items():
        if key not in rebuilt and not DATE_HEADER_RE.match(key):
            rebuilt[key] = entry

    return rebuilt


def parse_roster_pdf(file_path, year=None):
    """Parse every grid page of a roster PDF. Returns {date_str: day_result}.

    `year` (added 30/09): the calendar year to assume for every date in
    the roster — needed to convert printed local times to UTC correctly,
    since the offset depends on the exact date (DST). Defaults to the
    current UTC year if not given, matching what the app's own year
    picker defaults to.
    """
    import pdfplumber

    if year is None:
        year = datetime.now(timezone.utc).year

    all_results = {}
    with pdfplumber.open(file_path) as pdf:
        for page in pdf.pages:
            page_results = parse_page(page)
            all_results.update(page_results)
            # 02/10: pdfplumber caches each page's full layout/char tree
            # (via pdfminer) on the Page object, and `pdf.pages` keeps
            # every Page object alive for as long as `pdf` is open — so
            # without this, memory grows with every page processed and
            # is never released until the whole PDF is done. Render's
            # free tier (512MB) OOM-killed the service mid-request on a
            # real roster upload (confirmed in Render's Events log:
            # "Ran out of memory (used over 512MB)"); flushing each
            # page's cache as soon as we're done with it keeps peak
            # memory roughly constant instead of growing with page
            # count.
            page.flush_cache()

    resolve_utc_times(all_results, year)
    stitch_overnight_duties(all_results, year)
    all_results = promote_second_duties(all_results, year)

    return all_results

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

    flags = []
    i = 0
    n = len(tokens)
    continuation = False
    if texts[0] == "↓":
        continuation = True
        i = 1
        flags.append("continuation_from_previous_day")

    legs = []
    standbys = []
    delays = []
    report_time = None
    trailing_time = None

    while i < n:
        text, color = tokens[i]

        if text == "→":
            flags.append("continues_next_day")
            i += 1
            continue

        if text == "M":
            i += 1
            continue

        if text in DUTY_BLOCK_CODES:
            if i + 2 < n and TIME_RE.match(tokens[i + 1][0]) and TIME_RE.match(tokens[i + 2][0]):
                standbys.append({"code": text, "start": tokens[i + 1][0], "end": tokens[i + 2][0]})
                i += 3
                continue
            else:
                flags.append(f"unrecognised_standby_shape_at_{i}")
                i += 1
                continue

        if close(color, DELAY_COLOR) and text == "Delay":
            if i + 1 < n and TIME_RE.match(tokens[i + 1][0]):
                delays.append(tokens[i + 1][0])
                i += 2
                continue
            else:
                flags.append(f"unrecognised_delay_shape_at_{i}")
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
                legs.append(
                    {
                        "flightNumber": text,
                        "offBlock": off_val,
                        "offBlockActual": off_actual,
                        "origin": tokens[i + 2][0],
                        "destination": tokens[i + 3][0],
                        "onBlock": on_val,
                        "onBlockActual": on_actual,
                        "aircraft": tokens[i + 5][0].strip("[]"),
                    }
                )
                i += 6
                continue
            off2_val, off2_actual = block_time(tokens[i + 1][0]) if i + 1 < n else (None, None)
            if off2_val is not None and i + 2 < n and STATION_RE.match(tokens[i + 2][0]) and (
                i + 3 >= n or tokens[i + 3][0] == "→"
            ):
                legs.append(
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
                    }
                )
                i += 3
                continue
            else:
                flags.append(f"unrecognised_flight_shape_at_{i}")
                i += 1
                continue

        if continuation and legs == [] and standbys == [] and STATION_RE.match(text):
            if i + 2 < n and ACTUAL_TIME_RE.match(tokens[i + 1][0]) and AIRCRAFT_RE.match(tokens[i + 2][0]):
                legs.append(
                    {
                        "flightNumber": None,
                        "offBlock": None,
                        "origin": None,
                        "destination": text,
                        "onBlock": ACTUAL_TIME_RE.match(tokens[i + 1][0]).group(1),
                        "aircraft": tokens[i + 2][0].strip("[]"),
                        "continuedFromPreviousDay": True,
                    }
                )
                i += 3
                continue

        if TIME_RE.match(text):
            if report_time is None and not legs and not standbys:
                report_time = text
            else:
                trailing_time = text
            i += 1
            continue

        flags.append(f"unclassified_token:{text!r}_at_{i}")
        i += 1

    confident = not any(f.startswith("unrecognised") or f.startswith("unclassified") for f in flags)

    return {
        "status": "ok" if confident else "needs_review",
        "reportTime": report_time,
        "standbys": standbys,
        "legs": legs,
        "delays": delays,
        "trailingTime": trailing_time,
        "flags": flags,
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

        report_time = entry.get("reportTime")
        if report_time:
            report_utc = _to_utc(local_date, report_time, station_at_start)
            if report_utc:
                entry["reportTimeUtc"] = report_utc.isoformat()

        intercontinental = False
        for leg in entry.get("legs", []):
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
                        entry["intercontinentalTimeDifferenceHours"] = round(diff_hours)
                if _is_intercontinental_station(destination) and not _is_intercontinental_station(origin):
                    entry["transatlanticDirection"] = "westbound"
                elif _is_intercontinental_station(origin) and not _is_intercontinental_station(destination):
                    entry["transatlanticDirection"] = "eastbound"

            if destination:
                current_station = destination

        entry["intercontinental"] = intercontinental

        for standby in entry.get("standbys", []):
            start_utc = _to_utc(local_date, standby.get("start"), station_at_start)
            if start_utc:
                standby["startUtc"] = start_utc.isoformat()
            end_utc = _to_utc(local_date, standby.get("end"), station_at_start)
            if end_utc and start_utc and end_utc <= start_utc:
                end_utc = _to_utc(local_date + timedelta(days=1), standby.get("end"), station_at_start)
            if end_utc:
                standby["endUtc"] = end_utc.isoformat()

        trailing_time = entry.get("trailingTime")
        if trailing_time:
            trailing_utc = _to_utc(local_date, trailing_time, current_station)
            if trailing_utc:
                entry["trailingTimeUtc"] = trailing_utc.isoformat()

        entry["finishStation"] = current_station

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
        if "continues_next_day" not in entry.get("flags", []):
            continue
        if idx + 1 >= len(ordered_keys):
            continue
        next_entry = all_results[ordered_keys[idx + 1]]
        if "continuation_from_previous_day" not in next_entry.get("flags", []):
            continue

        arrival_leg = next((l for l in next_entry.get("legs", []) if l.get("continuedFromPreviousDay")), None)
        if not arrival_leg or "onBlockUtc" not in arrival_leg:
            continue

        # Fill this day's missing finish with the continuation's arrival,
        # and the continuation day's missing report with this day's
        # original report — so both rows describe the same complete duty.
        if not entry.get("trailingTimeUtc"):
            entry["trailingTime"] = arrival_leg["onBlock"]
            entry["trailingTimeUtc"] = arrival_leg["onBlockUtc"]
            entry.setdefault("flags", []).append("finish_time_from_next_day")
        if not next_entry.get("reportTimeUtc") and entry.get("reportTimeUtc"):
            next_entry["reportTime"] = entry.get("reportTime")
            next_entry["reportTimeUtc"] = entry["reportTimeUtc"]
            next_entry.setdefault("flags", []).append("report_time_from_previous_day")

    return all_results


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

    resolve_utc_times(all_results, year)
    stitch_overnight_duties(all_results, year)

    return all_results

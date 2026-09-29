"""Core roster-PDF parsing logic.

Ported unchanged from the prototype validated against two real Aer Lingus
rosters (30/09): 30/31 'ok' + 1/31 correctly-'empty' on the July roster,
31/31 'ok' on the August roster.

Extended here to loop over every page of the PDF (the prototype only
looked at page 0), so a roster PDF spanning more than one month is fully
parsed. Each page is expected to carry its own date-column header row.
"""

import re
from collections import defaultdict

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
    for i, date in enumerate(col_dates):
        ws = sorted(days.get(i, []), key=lambda w: w["top"])
        tokens = [
            (w["text"].strip().strip("​"), w.get("non_stroking_color"))
            for w in ws
            if w["text"].strip().strip("​") not in weekday_names
            and w["text"].strip().strip("​") != ""
        ]
        results[date] = parse_day(tokens)
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


def parse_roster_pdf(file_path):
    """Parse every grid page of a roster PDF. Returns {date_str: day_result}."""
    import pdfplumber

    all_results = {}
    with pdfplumber.open(file_path) as pdf:
        for page in pdf.pages:
            page_results = parse_page(page)
            all_results.update(page_results)
    return all_results

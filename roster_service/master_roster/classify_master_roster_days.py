"""
Classifies each raw Master Roster day-cell (list of stacked text lines, as
produced by parse_master_roster.py) into a structured day record matching
the shape the existing Dart rule engine expects (see lib/models/roster_day.dart
in the main app): status / kind / reportTime / trailingTime / legs / flags.

Confirmed with Guillermo (01/10) how the Master Roster prints flight duty
days: each flight line is "<flightNumber> <HH:MM>". For a day with 2+
recognised flight/duty-time lines, the FIRST line's time is the report time
(start of activity) and the LAST line's time is the finish time (already
includes the ~20 min post-flight debrief) — the Dart rule engine needs
nothing more than that pair. Times on lines in between are informational
only (intermediate flights' own times) and are not needed for Max Duty /
Min Rest, so they are kept on the leg record but never used to compute
report/finish.

Genuine data gap (never guessed, per the project's standing principle):
a day with exactly ONE recognised flight line has only a report time — no
finish. This happens for long-haul duties that continue past midnight
into the next calendar day (confirmed pattern: a single-flight day is
immediately followed, 1-2 days later, by a lone empty/missing day — the
overnight arrival the Master Roster doesn't print). These are left as
status "needs_review" with reportTime set and trailingTime null, so they
surface in the manual-review screen Elena approved (30/09) rather than
being silently estimated.

Day-off codes (F, GL, BH) and standby-duty lines (a 2-3 letter code
immediately followed by two HH:MM lines, e.g. "SD 9:00" / "17:00") are
also handled, mirroring the individual-roster parser's DAY_OFF_CODES /
STANDBY_CODES but adapted to this grid's "<code> <time>" / "<time>" line
shapes rather than token streams.
"""
import json
import re
import sys

FLIGHT_LINE_RE = re.compile(r"^\*?\s*(\d{1,4})\s+(\d{1,2}:\d{2})$")
BARE_TIME_RE = re.compile(r"^(\d{1,2}:\d{2})$")
CODE_TIME_RE = re.compile(r"^([A-Z]{1,4}\d?)\s+(\d{1,2}:\d{2})$")  # e.g. "SD 9:00", "K 13:00", "SEP1 7:00"
ANY_TIME_RE = re.compile(r"\d{1,2}:\d{2}")
# Known no-duty day codes, kept for readability/documentation — NOT an
# exhaustive gate: any first line with no time component, followed only by
# other no-time lines (course/training notes, crew names, briefing remarks),
# is treated as a no-duty day of that (possibly unfamiliar) code. There is
# nothing to compute on a day with zero printed times either way, so a code
# this list doesn't know by name (PRT, F-MB, etc.) is still handled safely.
DAY_OFF_CODES = {"F", "GL", "BH", "PRT"}
# Lines that are crew/roster annotations, never duty data (e.g. "J.DOYLE +",
# "COURSE: 4A-COMMAND", "br: PAPERLESS").
NOTE_LINE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9 .:'\-]*\+?$")
# Codes that are a genuine Standby duty in the regulatory sense (3.17/3.16 —
# the ones the Minimum Rest scenario detection treats differently, via
# RosterDay.standbys). Other duty codes with a time (BR briefing, PD/TD
# training, CRMI/SIM/etc.) are real duty but not a "standby" for that
# purpose, so they stay in `legs` and fall through to the ordinary
# base/outstation detection instead.
STANDBY_DUTY_CODES = {"SD", "STBH", "STBQ", "STBA", "STBB"}
# A flight number whose arrival got pushed past midnight (printed as "<num> >"
# in this grid — the Master Roster's equivalent of the individual roster's
# "→" continuation marker). No time to read off it; it just explains why no
# finish time follows.
CONTINUATION_RE = re.compile(r"^(\d{1,4})\s*>$")


def classify_day(lines):
    """lines: list[str], the stacked raw text for one pilot/date cell."""
    if not lines:
        return {"status": "empty", "kind": None, "reportTime": None,
                "trailingTime": None, "legs": [], "flags": []}

    # No line in the whole cell has a time in it at all -> this is a no-duty
    # day (a day-off code, possibly followed by course/crew/briefing notes),
    # whatever the exact code. Nothing to compute, so nothing to flag either.
    if not any(ANY_TIME_RE.search(l) for l in lines):
        return {"status": "ok", "kind": lines[0], "reportTime": None,
                "trailingTime": None, "legs": [],
                "flags": [f"day_off_notes:{l!r}" for l in lines[1:]]}

    legs = []  # [{flightNumber, time}], in printed order
    duty_times = []  # every recognised HH:MM that marks report/intermediate/finish
    flags = []

    for raw in lines:
        line = raw.strip()
        m = FLIGHT_LINE_RE.match(line)
        if m:
            num, t = m.groups()
            legs.append({"flightNumber": num, "time": t})
            duty_times.append(t)
            continue
        m = CODE_TIME_RE.match(line)
        if m:
            code, t = m.groups()
            legs.append({
                "flightNumber": None,
                "dutyCode": code,
                "time": t,
                "isStandby": code in STANDBY_DUTY_CODES,
            })
            duty_times.append(t)
            continue
        m = BARE_TIME_RE.match(line)
        if m:
            duty_times.append(m.group(1))
            continue
        m = CONTINUATION_RE.match(line)
        if m:
            legs.append({"flightNumber": m.group(1), "time": None, "continuesNextDay": True})
            flags.append("continues_next_day")
            continue
        if NOTE_LINE_RE.match(line):
            flags.append(f"note_line:{line!r}")
            continue
        flags.append(f"unrecognised_line:{line!r}")

    if not duty_times:
        # Nothing with a time was recognised at all — can't say anything.
        flags.append("no_times_recognised")
        return {"status": "needs_review", "kind": None, "reportTime": None,
                "trailingTime": None, "legs": legs, "flags": flags}

    report_time = duty_times[0]
    if len(duty_times) >= 2:
        trailing_time = duty_times[-1]
        status = "needs_review" if flags else "ok"
    else:
        # Single time recognised: report only. Genuine gap (overnight/
        # continuing long-haul duty) — never guess a finish time.
        trailing_time = None
        flags.append("single_time_only_likely_overnight_continuation")
        status = "needs_review"

    return {
        "status": status,
        "kind": None,
        "reportTime": report_time,
        "trailingTime": trailing_time,
        "legs": legs,
        "flags": flags,
    }


def classify_roster(records):
    """records: the list from parse_master_roster.py's main() (or out4.json)."""
    out = []
    for rec in records:
        days = {date: classify_day(lines) for date, lines in rec["days"].items()}
        out.append({
            "name": rec["name"],
            "seniority": rec.get("seniority"),
            "id": rec.get("id"),
            "notes": rec.get("notes", []),
            "page": rec.get("page"),
            "days": days,
        })
    return out


def stats(classified):
    from collections import Counter
    c = Counter()
    flag_reasons = Counter()
    for rec in classified:
        for date, day in rec["days"].items():
            c[day["status"]] += 1
            if day["status"] == "needs_review":
                for f in day["flags"]:
                    key = f.split(":")[0]
                    flag_reasons[key] += 1
    return c, flag_reasons


if __name__ == "__main__":
    in_path = sys.argv[1] if len(sys.argv) > 1 else "out4.json"
    out_path = sys.argv[2] if len(sys.argv) > 2 else "master_roster_classified.json"
    records = json.load(open(in_path))
    classified = classify_roster(records)
    json.dump(classified, open(out_path, "w"), indent=2, ensure_ascii=False)
    c, reasons = stats(classified)
    print("Status counts:", dict(c))
    print("needs_review reasons:", dict(reasons))
    print(f"Wrote {out_path}")

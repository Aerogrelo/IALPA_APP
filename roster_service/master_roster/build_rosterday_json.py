"""
Final stage of the Master Roster pipeline: turns the classified+station-
enriched per-day records into JSON matching exactly the shape
lib/models/roster_day.dart's RosterDay.fromJson expects, so the Dart batch
audit engine can read a Master Roster PDF's output with the IDENTICAL
model class already used (and tested) for the single-pilot roster importer
— no parallel model needed.

Pipeline so far: parse_master_roster.py (raw PDF -> stacked text lines per
pilot/day) -> classify_master_roster_days.py (raw lines -> status/report/
trailing/legs) -> enrich_with_stations.py (adds reportStation/
finishStation/intercontinental via flight_routes.json) -> THIS SCRIPT
(adds reportTimeUtc/trailingTimeUtc, splits legs into RosterDay's
legs/standbys, and fills transatlanticDirection/
intercontinentalTimeDifferenceHours).

Time zone (confirmed 01/10 from the real 330_CP roster's own header —
"ALL Times in LOCAL BASE"): unlike the single-pilot roster (local to
EACH station, confirmed 30/09), every time in the Master Roster is
Dublin local time, so converting to UTC is one timezone for the whole
file, not a per-leg lookup. Uses zoneinfo "Europe/Dublin" so DST (IST
vs GMT) is handled correctly for whatever dates the roster covers.

intercontinentalTimeDifferenceHours is a seasonal approximation (documented
limitation, same spirit as "never silently guess" but this field only
moves a formula's MARGIN, never whether a day is checked at all — see the
01/10 project briefing note): a fixed UTC-offset-hours table for the North
American stations Aer Lingus's A330 flies to, valid for the Sep/Oct DST
state both sides of the Atlantic. A roster spanning the actual DST
transition weekend would need this made date-aware; flagged here for
later, not silently fixed.
"""
import json
import re
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

DUBLIN = ZoneInfo("Europe/Dublin")
DATE_RE = re.compile(r"^([A-Z][a-z]{2})(\d{2})$")
MONTHS = {m: i + 1 for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])}

STANDBY_DUTY_CODES = {"SD", "STBH", "STBQ", "STBA", "STBB"}

# UTC offset (hours, standard+DST already applied for the period a roster
# covers) for the North American stations in flight_routes.json's data.
# Positive = west of UTC (i.e. Dublin time minus this = local time there).
NA_UTC_OFFSET_SEP_OCT = {
    "JFK": 4, "BOS": 4, "EWR": 4, "IAD": 4, "PHL": 4, "ATL": 4, "MCO": 4,
    "CLT": 4, "MIA": 4, "ORL": 4, "DTW": 4, "MDW": 4, "YYZ": 4, "YUL": 4,
    "ORD": 5, "MSP": 5, "AUS": 5, "DFW": 5,
    "DEN": 6,
    "LAX": 7, "SFO": 7, "SEA": 7, "LAS": 7,
}


def parse_date(date_col, year):
    m = DATE_RE.match(date_col)
    mon, day = MONTHS[m.group(1)], int(m.group(2))
    return mon, day


def to_utc(date_col, hhmm, year, month_rollover_year):
    """hhmm like '9:00' or '17:00', date_col like 'Oct28'. Handles the
    roster period crossing a year boundary (Dec->Jan) via
    month_rollover_year, a mutable dict carrying the running year."""
    mon, day = parse_date(date_col, year)
    if month_rollover_year["prev_month"] is not None and mon < month_rollover_year["prev_month"]:
        month_rollover_year["year"] += 1
    month_rollover_year["prev_month"] = mon
    h, mi = (int(x) for x in hhmm.split(":"))
    local = datetime(month_rollover_year["year"], mon, day, h, mi, tzinfo=DUBLIN)
    return local.astimezone(ZoneInfo("UTC"))


def build(enriched, year):
    out = []
    for rec in enriched:
        pilot_out = {
            "name": rec["name"], "seniority": rec.get("seniority"),
            "id": rec.get("id"), "days": {},
        }
        ymy = {"year": year, "prev_month": None}
        prev_day_was_standby = False
        for date_col, day in rec["days"].items():
            legs_out, standbys_out = [], []
            for leg in day.get("legs", []):
                if leg.get("flightNumber"):
                    legs_out.append({
                        "flightNumber": leg["flightNumber"],
                        "offBlock": leg.get("time"),
                        "origin": leg.get("origin"),
                        "destination": leg.get("destination"),
                    })
                elif leg.get("isStandby"):
                    standbys_out.append({
                        "code": leg.get("dutyCode"), "start": leg.get("time"),
                    })
                else:
                    # ground duty with a time but not a regulatory standby
                    # (BR/PD/TD/training codes) -> keep as an (uncredited)
                    # leg entry so it still carries a time, just never
                    # triggers the afterStandby rest scenario.
                    legs_out.append({
                        "flightNumber": None, "dutyCode": leg.get("dutyCode"),
                        "offBlock": leg.get("time"),
                        "origin": None, "destination": None,
                    })

            report_utc = to_utc(date_col, day["reportTime"], year, ymy) \
                if day.get("reportTime") else None
            trailing_utc = to_utc(date_col, day["trailingTime"], year, ymy) \
                if day.get("trailingTime") else None

            direction = None
            time_diff_hours = None
            if day.get("intercontinental"):
                origin, dest = day.get("reportStation"), day.get("finishStation")
                offset = NA_UTC_OFFSET_SEP_OCT.get(origin) or NA_UTC_OFFSET_SEP_OCT.get(dest)
                if offset is not None:
                    time_diff_hours = offset
                    # Westbound = DUB -> NA (report at DUB); eastbound = NA -> DUB.
                    direction = "westbound" if origin == "DUB" else (
                        "eastbound" if dest == "DUB" else None)

            missing_fields = []
            if day["status"] == "needs_review":
                if day.get("reportTime") and not day.get("trailingTime"):
                    missing_fields.append("finishTime")
            if day.get("intercontinental"):
                # Confirmed 01/10 against the real 330_CP roster: crew
                # complement (two-pilot/augmented/heavy) is NEVER printed
                # anywhere in the Master Roster, for any fleet. Per
                # Elena's 01/10 instruction, this is surfaced as an
                # explicit "needs input" field, not a generic review flag.
                missing_fields.append("crewType")

            status = day["status"]
            if missing_fields and status == "ok":
                status = "needs_review"

            pilot_out["days"][date_col] = {
                "status": status,
                "kind": day.get("kind"),
                "reportTime": day.get("reportTime"),
                "trailingTime": day.get("trailingTime"),
                "reportTimeUtc": report_utc.isoformat() if report_utc else None,
                "trailingTimeUtc": trailing_utc.isoformat() if trailing_utc else None,
                "legs": legs_out,
                "standbys": standbys_out,
                "flags": day.get("flags", []),
                "missingFields": missing_fields,
                "reportStation": day.get("reportStation"),
                "finishStation": day.get("finishStation"),
                "intercontinental": day.get("intercontinental", False),
                "transatlanticDirection": direction,
                "intercontinentalTimeDifferenceHours": time_diff_hours,
            }
        out.append(pilot_out)
    return out


if __name__ == "__main__":
    enriched_path = sys.argv[1] if len(sys.argv) > 1 else "master_roster_enriched.json"
    year = int(sys.argv[2]) if len(sys.argv) > 2 else 2026
    out_path = sys.argv[3] if len(sys.argv) > 3 else "master_roster_rosterday.json"
    enriched = json.load(open(enriched_path))
    built = build(enriched, year)
    json.dump(built, open(out_path, "w"), indent=2, ensure_ascii=False, default=str)
    print(f"Wrote {out_path} ({len(built)} pilots)")

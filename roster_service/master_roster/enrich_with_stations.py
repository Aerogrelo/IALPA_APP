"""
Adds station info to the classified Master Roster days:
- Each leg gets origin/destination from flight_routes.json (when known).
- Each day gets reportStation/finishStation: reportStation = first leg's
  origin if known, else carried over from the previous day's finishStation
  (a pilot doesn't teleport on a day off or standby-at-the-same-place);
  finishStation = last leg's destination if known, else carried forward
  unchanged (still there).
- Each day gets intercontinental (any leg touches the US/CA network, same
  INTERCONTINENTAL_COUNTRIES convention as roster_parser.py) — needs an
  IATA->country table, so this script keeps a small one inline for the
  stations actually seen in the 31 confirmed routes' destinations.

Per pilot, days are walked in chronological order (the dict preserves PDF
column order, which is chronological) so the station carries forward
correctly across day-offs/standbys.

Never silently invents a station: if a day's legs are unresolved AND the
previous day's finishStation is unknown too, both stations stay null and
the day keeps whatever status classify_master_roster_days.py gave it
(this script only enriches, never changes status/report/trailing times).
"""
import json
import sys

# Minimal IATA -> country map, built only from the airports actually in
# flight_routes.json's destinations (31/01/10 route-gathering sessions).
# North America (Aer Lingus Intercontinental network) is what matters here;
# everything else defaults to "other" and is therefore never flagged
# Intercontinental, matching roster_parser.py's INTERCONTINENTAL_COUNTRIES.
NORTH_AMERICA_STATIONS = {
    "JFK", "BOS", "ORD", "LAX", "SFO", "MIA", "EWR", "IAD", "ORL",
    "SEA", "DFW", "DEN", "YYZ", "YUL", "PHL", "MCO", "CLT", "ATL",
    "AUS", "LAS", "MSP", "DTW", "MDW",
}


def enrich(classified, routes):
    for rec in classified:
        prev_finish = None
        for date, day in rec["days"].items():
            for leg in day.get("legs", []):
                num = leg.get("flightNumber")
                route = routes.get(num) if num else None
                if route:
                    leg["origin"] = route["origin"]
                    leg["destination"] = route["destination"]
                else:
                    leg["origin"] = None
                    leg["destination"] = None

            legs = day.get("legs", [])
            flight_legs = [l for l in legs if l.get("origin") or l.get("destination")]

            report_station = flight_legs[0]["origin"] if flight_legs else None
            finish_station = flight_legs[-1]["destination"] if flight_legs else None

            if report_station is None:
                report_station = prev_finish
            if finish_station is None:
                # No new info this day -> still wherever they were,
                # unless we resolved a report station above.
                finish_station = finish_station or report_station

            day["reportStation"] = report_station
            day["finishStation"] = finish_station
            day["intercontinental"] = any(
                l.get("origin") in NORTH_AMERICA_STATIONS
                or l.get("destination") in NORTH_AMERICA_STATIONS
                for l in flight_legs
            )
            prev_finish = finish_station if finish_station else prev_finish
    return classified


def coverage_stats(classified):
    total_legs = resolved_legs = 0
    total_days = station_known_days = 0
    for rec in classified:
        for date, day in rec["days"].items():
            total_days += 1
            if day.get("reportStation") and day.get("finishStation"):
                station_known_days += 1
            for leg in day.get("legs", []):
                if leg.get("flightNumber"):
                    total_legs += 1
                    if leg.get("origin") or leg.get("destination"):
                        resolved_legs += 1
    return total_legs, resolved_legs, total_days, station_known_days


if __name__ == "__main__":
    classified_path = sys.argv[1] if len(sys.argv) > 1 else "master_roster_classified.json"
    routes_path = sys.argv[2] if len(sys.argv) > 2 else "flight_routes_merged.json"
    out_path = sys.argv[3] if len(sys.argv) > 3 else "master_roster_enriched.json"

    classified = json.load(open(classified_path))
    routes = json.load(open(routes_path))
    routes["462"] = {"origin": "DUB", "destination": "CTA"}  # confirmed 01/10

    enriched = enrich(classified, routes)
    json.dump(enriched, open(out_path, "w"), indent=2, ensure_ascii=False)

    total_legs, resolved_legs, total_days, station_known_days = coverage_stats(enriched)
    print(f"Legs with a known route: {resolved_legs}/{total_legs} "
          f"({resolved_legs/total_legs:.1%})")
    print(f"Days with both report & finish station known: "
          f"{station_known_days}/{total_days} ({station_known_days/total_days:.1%})")
    print(f"Wrote {out_path}")

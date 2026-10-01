"""
Prototype parser for the IALPA "Master Roster" PDF (grid format: all pilots x all days),
as opposed to the per-pilot roster format already supported by roster_service/roster_parser.py.

Output: one JSON record per (pilot, date) with report/finish times (first/last line in the
cell) and the raw stacked lines, plus free-text notes per pilot/date.

This is a first pass to validate we can read the layout reliably before deciding whether/how
to plug it into the existing rule engine.
"""
import json
import re
import sys
from collections import defaultdict

import pdfplumber

DATE_RE = re.compile(r"^[A-Z][a-z]{2}\d{2}$")  # e.g. Oct20, Nov02
TIME_RE = re.compile(r"^\d{1,2}:\d{2}$")
BLOCK_ANCHOR_X = 25  # words with x0 below this, on the "DUB ..." line, start a pilot block


def cluster_lines(words, tol=2.0):
    """Group words into text-lines by their 'top' coordinate (handles tiny float jitter)."""
    lines = []
    for w in sorted(words, key=lambda w: w["top"]):
        placed = False
        for line in lines:
            if abs(line["top"] - w["top"]) <= tol:
                line["words"].append(w)
                placed = True
                break
        if not placed:
            lines.append({"top": w["top"], "words": [w]})
    lines.sort(key=lambda l: l["top"])
    for line in lines:
        line["words"].sort(key=lambda w: w["x0"])
    return lines


def parse_page(page, year_hint):
    # x_tolerance=1 keeps the PDF from gluing two adjacent-but-distinct tokens
    # together (e.g. a duty code's finish time run into the next column's code,
    # like "10:00CS" instead of "10:00" / "CS") — the default (3) merges them.
    words = page.extract_words(use_text_flow=False, keep_blank_chars=False, x_tolerance=1)
    lines = cluster_lines(words)

    # --- find the date header row: a line containing >= 5 tokens matching DATE_RE
    header_line = None
    for line in lines:
        date_words = [w for w in line["words"] if DATE_RE.match(w["text"])]
        if len(date_words) >= 5:
            header_line = line
            date_words.sort(key=lambda w: w["x0"])
            break
    if header_line is None:
        return []  # not a grid page (e.g. cover page)

    date_cols = [(w["text"], w["x0"]) for w in date_words]
    # column boundaries = midpoints between consecutive date x0s
    xs = [x for _, x in date_cols]
    bounds = []
    for i, (_, x) in enumerate(date_cols):
        left = (xs[i - 1] + x) / 2 if i > 0 else x - (xs[1] - xs[0]) / 2
        right = (xs[i + 1] + x) / 2 if i < len(date_cols) - 1 else x + (xs[-1] - xs[-2]) / 2
        bounds.append(left)
    bounds.append(1e9)

    def col_for_x(x0):
        for i in range(len(date_cols)):
            if bounds[i] <= x0 < bounds[i + 1]:
                return date_cols[i][0]
        return None

    grid_left_edge = bounds[0]

    # --- find pilot-block anchor lines: leftmost word is "DUB" (or similar 3-letter base) at x0<25
    anchor_idx = []
    for i, line in enumerate(lines):
        if line["top"] <= header_line["top"] + 2:
            continue
        first = line["words"][0]
        if first["x0"] < BLOCK_ANCHOR_X and re.match(r"^[A-Z]{3}$", first["text"]):
            anchor_idx.append(i)

    records = []
    for bi, idx in enumerate(anchor_idx):
        start_top = lines[idx]["top"]
        end_top = lines[anchor_idx[bi + 1]]["top"] if bi + 1 < len(anchor_idx) else 1e9
        block_lines = [l for l in lines if start_top <= l["top"] < end_top]

        # name: second line's leftmost words (x0 < grid_left_edge), joined
        name = None
        seniority = None
        pilot_id = None
        note_lines = []
        note_line_ids = set()  # id() of block_lines entries fully consumed as notes,
        # so the grid pass below skips them too.
        note_date_re = re.compile(r"^\d{2}\.\d{2}\.\d{4}$")
        for li, line in enumerate(block_lines):
            all_text = " ".join(w["text"] for w in line["words"])
            if re.fullmatch(r"_+", all_text.replace(" ", "")):
                continue  # the "____" rule between this pilot and the next — not data

            sorted_words = sorted(line["words"], key=lambda w: w["x0"])
            # A note line is identified by its FIRST word being a "DD.MM.YYYY" date,
            # regardless of where it sits relative to the separator rule — in blocks
            # with enough stacked legs to push the Seniority/ID text down, a note for
            # that same week can appear before the rule, not after it. The whole line
            # (both margins) is note text, never grid data, however far right it runs.
            if sorted_words and note_date_re.match(sorted_words[0]["text"]):
                rest = " ".join(w["text"] for w in sorted_words[1:]).strip()
                note_lines.append({"date": sorted_words[0]["text"], "text": rest})
                note_line_ids.add(id(line))
                continue

            left_words = [w for w in line["words"] if w["x0"] < grid_left_edge]
            if not left_words:
                continue
            text = " ".join(w["text"] for w in left_words)
            if li == 1 and name is None and "Seniority" not in text:
                name = text
            m = re.search(r"Seniority No\s*:\s*(\d+)", text)
            if m:
                seniority = m.group(1)
            elif re.match(r"^\d{4,6}$", text.strip()):
                pilot_id = text.strip()

        # grid: bucket words by column, preserving line order (line index = leg index)
        col_stacks = defaultdict(list)  # date -> list of (top, line_text)
        for line in block_lines:
            if id(line) in note_line_ids:
                continue
            all_text = " ".join(w["text"] for w in line["words"])
            if re.fullmatch(r"_+", all_text.replace(" ", "")):
                continue
            grid_words = [w for w in line["words"] if w["x0"] >= grid_left_edge]
            if not grid_words:
                continue

            # Some cells in the source PDF have zero gap between a time and the
            # following cell's duty code (e.g. "9:00PSBT" instead of "9:00" /
            # "PSBT"), which extract_words can't separate no matter the
            # x_tolerance — there's genuinely no space character there. Detect
            # that generically (a HH:MM run immediately followed by an
            # uppercase code, no hardcoded code list) and split it, moving the
            # second half into the next date column — gluing only ever happens
            # across one column boundary, never within a cell's own code+time.
            expanded = []
            glue_re = re.compile(r"^(\d{1,2}:\d{2})([A-Z][A-Z0-9]*)$")
            for w in grid_words:
                m = glue_re.match(w["text"])
                if m:
                    expanded.append({"x0": w["x0"], "text": m.group(1)})
                    expanded.append({"x0": w["x0"], "text": m.group(2), "_glued_next": True})
                else:
                    expanded.append(w)

            by_col = defaultdict(list)
            for w in expanded:
                if w.get("_glued_next"):
                    orig_col = col_for_x(w["x0"])
                    orig_idx = next((i for i, (d, _) in enumerate(date_cols) if d == orig_col), None)
                    if orig_idx is not None and orig_idx + 1 < len(date_cols):
                        c = date_cols[orig_idx + 1][0]
                        w = {"x0": bounds[orig_idx + 1], "text": w["text"]}
                    else:
                        c = orig_col
                else:
                    c = col_for_x(w["x0"])
                if c:
                    by_col[c].append(w)
            for c, ws in by_col.items():
                ws.sort(key=lambda w: w["x0"])
                text = " ".join(w["text"] for w in ws)
                col_stacks[c].append((line["top"], text))

        day_cells = {}
        for date_str, entries in col_stacks.items():
            entries.sort(key=lambda e: e[0])
            raw_lines = [t for _, t in entries if set(t.strip()) != {"_"}]
            if raw_lines:
                day_cells[date_str] = raw_lines

        records.append(
            {
                "name": name,
                "seniority": seniority,
                "id": pilot_id,
                "notes": note_lines,
                "days": day_cells,
            }
        )
    return records


def main(path, year_hint=2025):
    all_records = []
    with pdfplumber.open(path) as pdf:
        for pno, page in enumerate(pdf.pages):
            recs = parse_page(page, year_hint)
            for r in recs:
                r["page"] = pno + 1
            all_records.extend(recs)
    return all_records


if __name__ == "__main__":
    path = sys.argv[1]
    out = main(path)
    print(json.dumps(out, indent=2, ensure_ascii=False))

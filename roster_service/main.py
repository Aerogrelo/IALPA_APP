"""Roster-PDF parsing service.

Small HTTP API for the IALPA App: the Flutter app uploads a pilot's
roster PDF, this service parses it with the validated logic in
roster_parser.py, and returns structured JSON. The uploaded file is
deleted immediately after parsing (success or failure) — this service
does not store rosters.

Run locally:
    pip install -r requirements.txt
    uvicorn main:app --reload

Deploy: see README.md for Render/Railway instructions.
"""

import os
import tempfile

from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from roster_parser import parse_roster_pdf

app = FastAPI(title="IALPA App — Roster Parser")

# The Flutter app runs as a web page (flutter run -d chrome during
# development, and the same is true of a real web deployment later),
# so the browser enforces CORS on requests from that page's origin to
# this service's different origin. Without this, the browser blocks
# the request before it ever reaches the routes below — curl/native
# apps aren't subject to CORS, which is why this wasn't caught by the
# earlier curl test. Wide open (`*`) is fine here: there's no cookie
# or session auth to protect, only the X-API-Key header, which CORS
# doesn't weaken.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Simple shared-secret check so this isn't a wide-open upload endpoint.
# Set ROSTER_API_KEY in the deployment's environment variables; the app
# sends the same value in the X-API-Key header. If ROSTER_API_KEY isn't
# set, the check is skipped (useful for local testing only — always set
# it once deployed).
API_KEY = os.environ.get("ROSTER_API_KEY")


def _check_api_key(x_api_key: str | None):
    if API_KEY and x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/parse-roster")
async def parse_roster(
    file: UploadFile = File(...),
    x_api_key: str | None = Header(default=None),
):
    _check_api_key(x_api_key)

    if file.content_type not in ("application/pdf", "application/octet-stream"):
        raise HTTPException(status_code=400, detail="Expected a PDF file")

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
            tmp_path = tmp.name
            contents = await file.read()
            tmp.write(contents)

        results = parse_roster_pdf(tmp_path)
        return JSONResponse({"days": results})
    except Exception as exc:  # noqa: BLE001 — surface parse failures plainly
        raise HTTPException(status_code=422, detail=f"Could not parse roster: {exc}") from exc
    finally:
        # Delete the roster immediately, whether parsing succeeded or not.
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)

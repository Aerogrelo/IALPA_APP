import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Configuration for the roster-parsing cloud service (`roster_service/`
/// at the repo root — a small FastAPI service, deployed separately on
/// Render; see that folder's README.md for what it does and why it's a
/// separate service rather than parsing on-device).
///
/// **29/09 — temporary, flagged for later:** the URL and key are
/// hardcoded here for the pilot-testing phase, which means they're
/// readable by anyone who decompiles the app. Fine for a handful of
/// pilots testing a prototype; before this goes out more widely, this
/// should move to something that isn't baked into the compiled app (a
/// short auth step, or a key issued per pilot).
class RosterServiceConfig {
  static const String baseUrl = 'https://ialpa-app.onrender.com';
  static const String apiKey = 'c8345281f1993c1397df7462ec9e12c8';
}

/// Thrown when the roster service can't be reached, or returns something
/// other than a successful parse.
class RosterServiceException implements Exception {
  RosterServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Uploads a roster PDF to the parsing service and returns its per-day
/// results: a map from date string ('02/07', day/month — the roster PDF's
/// own day-grid header has no year on it, see [RosterDay]) to that day's
/// parsed data. The PDF is sent once and is not kept by the service — it
/// deletes the upload immediately after parsing, success or failure (see
/// `roster_service/main.py`).
///
/// [year] (added 30/09): the roster prints every time as LOCAL TIME AT
/// THE STATION where it happens, not UTC, so the service needs a year to
/// convert correctly (the UTC offset depends on the exact date, because
/// of DST) — it's the same year the picker dialog's year stepper shows,
/// and re-uploading with a corrected year re-does that conversion.
/// Defaults to the current UTC year if omitted.
Future<Map<String, dynamic>> uploadRosterPdf(
  Uint8List bytes,
  String filename, {
  int? year,
}) async {
  final uri = Uri.parse('${RosterServiceConfig.baseUrl}/parse-roster');
  final request = http.MultipartRequest('POST', uri)
    ..headers['X-API-Key'] = RosterServiceConfig.apiKey
    ..fields['year'] = (year ?? DateTime.now().toUtc().year).toString()
    ..files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

  final http.StreamedResponse streamed;
  try {
    // Render's free tier spins down after inactivity — the first request
    // in a while can take several seconds just to wake it back up. 60s
    // comfortably covers that; anything else surfaces as a real error.
    streamed = await request.send().timeout(const Duration(seconds: 60));
  } catch (e) {
    throw RosterServiceException(
      'Could not reach the roster service. Check your connection and try '
      'again.',
    );
  }

  final response = await http.Response.fromStream(streamed);
  if (response.statusCode != 200) {
    throw RosterServiceException(
      'The roster service could not read that file (HTTP '
      '${response.statusCode}). Make sure it\'s the "Personal Crew '
      'Schedule Report" PDF from Aer Lingus.',
    );
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  return decoded['days'] as Map<String, dynamic>;
}

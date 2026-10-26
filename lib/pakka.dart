/// Pakka, OpenPak's diagnostic assistant: service checks and guided
/// diagnosis of connection problems.
///
/// Hand-written like [OpenPakApi]: three endpoints of JSON in and JSON out
/// (`GET /healthz`, `POST /v1/runs`, `POST /v1/investigations`), served by the
/// Go harness in `platforms/core/pakka`. Failures are [ApiException], so the
/// UI words them with the same [apiErrorText] and [LoadFailure] as every other
/// call. Pakka sends no error codes and takes no bearer; there is nothing to
/// sign out of.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

/// One check's outcome, as the harness reports it: `pass`, `fail`, `error`
/// or `skipped`. Kept as the raw word so a newer harness still parses.
class PakkaCheckResult {
  PakkaCheckResult({
    required this.checkId,
    required this.outcome,
    required this.summary,
    this.source = '',
    this.evidence = const {},
    this.durationMs = 0,
    this.timestamp,
  });

  final String checkId;
  final String outcome;
  final String summary;

  /// Where the result came from (`fixture`, `harness`). Empty on an
  /// investigation's slimmed results, which carry only what the finding cites.
  final String source;
  final Map<String, dynamic> evidence;
  final int durationMs;
  final DateTime? timestamp;

  factory PakkaCheckResult.fromJson(Map<String, dynamic> j) => PakkaCheckResult(
    checkId: j['check_id'] as String? ?? '',
    outcome: j['outcome'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    source: j['source'] as String? ?? '',
    evidence: j['evidence'] is Map<String, dynamic> ? j['evidence'] as Map<String, dynamic> : const {},
    durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
    timestamp: DateTime.tryParse(j['ts'] as String? ?? ''),
  );
}

/// One diagnostic run: the ordered results of the harness's check suite.
class PakkaRun {
  PakkaRun({
    required this.schema,
    required this.runId,
    required this.scenario,
    required this.mode,
    this.started,
    this.finished,
    this.results = const [],
  });

  final String schema;
  final String runId;
  final String scenario;
  final String mode;
  final DateTime? started;
  final DateTime? finished;
  final List<PakkaCheckResult> results;

  factory PakkaRun.fromJson(Map<String, dynamic> j) => PakkaRun(
    schema: j['schema'] as String? ?? '',
    runId: j['run_id'] as String? ?? '',
    scenario: j['scenario'] as String? ?? '',
    mode: j['mode'] as String? ?? '',
    started: DateTime.tryParse(j['started'] as String? ?? ''),
    finished: DateTime.tryParse(j['finished'] as String? ?? ''),
    results: [
      for (final r in (j['results'] as List? ?? const []).whereType<Map<String, dynamic>>())
        PakkaCheckResult.fromJson(r),
    ],
  );
}

/// What Pakka concluded. [diagnosis] is one of `local-failure`,
/// `service-outage`, `healthy` or `insufficient-evidence`; [evidence] names
/// only the checks that actually ran. [recommendedNext] is advice to show,
/// never anything the app carries out.
class PakkaFinding {
  PakkaFinding({
    required this.diagnosis,
    required this.summary,
    this.evidence = const [],
    this.recommendedNext = '',
  });

  final String diagnosis;
  final String summary;
  final List<String> evidence;
  final String recommendedNext;

  factory PakkaFinding.fromJson(Map<String, dynamic> j) => PakkaFinding(
    diagnosis: j['diagnosis'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    evidence: (j['evidence'] as List? ?? const []).whereType<String>().toList(growable: false),
    recommendedNext: j['recommended_next'] as String? ?? '',
  );
}

/// A diagnosis with the check results behind it.
class PakkaInvestigation {
  PakkaInvestigation({required this.finding, this.results = const []});
  final PakkaFinding finding;
  final List<PakkaCheckResult> results;

  factory PakkaInvestigation.fromJson(Map<String, dynamic> j) => PakkaInvestigation(
    finding: PakkaFinding.fromJson((j['finding'] as Map?)?.cast<String, dynamic>() ?? const {}),
    results: [
      for (final r in (j['results'] as List? ?? const []).whereType<Map<String, dynamic>>())
        PakkaCheckResult.fromJson(r),
    ],
  );
}

class PakkaApi {
  PakkaApi({required this.baseUrl, http.Client? client}) : _http = client ?? http.Client();

  /// The harness root, e.g. `https://openpak.org/pakka` once it is served, or
  /// `http://10.0.2.2:24800` against a local harness from the emulator.
  final String baseUrl;
  final http.Client _http;

  /// The app's language as a BCP-47 tag, sent as Accept-Language on every
  /// call like [OpenPakApi.language].
  String? language;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers({bool json = false}) => {
    if (language != null) 'Accept-Language': language!,
    if (json) 'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> _decode(http.Response r) async {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return {};
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    var message = 'Request failed (${r.statusCode})';
    var fromServer = false;
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['error'] is String) {
        message = body['error'] as String;
        fromServer = true;
      }
    } catch (_) {
      // A non-JSON error body is a proxy or an outage, not something to show.
    }
    throw ApiException(r.statusCode, message, fromServer: fromServer);
  }

  /// GET /healthz — the harness answers `{"status":"ok"}`.
  Future<void> ping() async {
    final r = await _http.get(_uri('/healthz'), headers: _headers());
    await _decode(r);
  }

  /// POST /v1/runs — the check suite, live against the configured targets.
  /// [scenario] only labels a live run; fixture scenarios are the harness's
  /// own development vocabulary and the app never sends one.
  Future<PakkaRun> run({String mode = 'live', String? scenario}) async {
    final r = await _http.post(
      _uri('/v1/runs'),
      headers: _headers(json: true),
      body: jsonEncode({if (scenario != null) 'scenario': scenario, 'mode': mode}),
    );
    return PakkaRun.fromJson(await _decode(r));
  }

  /// POST /v1/investigations — a guided diagnosis of [symptoms]. Empty
  /// symptoms are the harness's "unspecified connection problem".
  Future<PakkaInvestigation> investigate({String mode = 'live', String? scenario, String symptoms = ''}) async {
    final r = await _http.post(
      _uri('/v1/investigations'),
      headers: _headers(json: true),
      body: jsonEncode({if (scenario != null) 'scenario': scenario, 'mode': mode, 'symptoms': symptoms}),
    );
    return PakkaInvestigation.fromJson(await _decode(r));
  }
}

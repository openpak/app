import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/l10n.dart';
import 'package:openpak/pakka.dart';
import 'package:openpak/pakka_page.dart';
import 'package:openpak/theme.dart';
import 'package:openpak/titles_page.dart';
import 'package:openpak/widgets.dart';

import 'localized.dart';

// The shapes below are the harness's own: captured from `go run .` in
// platforms/core/pakka, fixture mode, so the client parses what the server
// really sends rather than what its tests believe.
const _runBody = {
  'schema': 'pakka.evidence/v0',
  'run_id': '1204f48464ffec24',
  'scenario': 'service-outage',
  'mode': 'fixture',
  'started': '2026-10-26T20:49:13.819849997Z',
  'finished': '2026-10-26T20:49:13.819879663Z',
  'results': [
    {
      'check_id': 'dns.resolve',
      'ts': '2026-10-26T20:49:13.819850267Z',
      'source': 'fixture',
      'outcome': 'pass',
      'summary': 'synthetic: resolve ok',
      'evidence': {
        'addrs': ['192.0.2.1'],
        'host': 'example.invalid',
      },
      'duration_ms': 2,
    },
    {
      'check_id': 'tcp.connect',
      'ts': '2026-10-26T20:49:13.819850568Z',
      'source': 'fixture',
      'outcome': 'pass',
      'summary': 'synthetic: connect ok',
      'evidence': {'addr': '192.0.2.1:443'},
      'duration_ms': 3,
    },
    {
      'check_id': 'http.health',
      'ts': '2026-10-26T20:49:13.819850708Z',
      'source': 'fixture',
      'outcome': 'fail',
      'summary': 'synthetic: 503 from health endpoint; service outage suspected',
      'evidence': {'status': 503, 'url': 'https://example.invalid/health'},
      'duration_ms': 5,
    },
  ],
};

const _investigationBody = {
  'finding': {
    'diagnosis': 'local-failure',
    'summary': 'synthetic: local environment misconfigured',
    'evidence': ['dns.resolve', 'tcp.connect'],
    'recommended_next': 'synthetic: re-run Switch Setup and retest',
  },
  'results': [
    {'check_id': 'dns.resolve', 'outcome': 'pass', 'summary': 'resolve localhost: 2 addr(s)'},
    {'check_id': 'tcp.connect', 'outcome': 'skipped', 'summary': 'no TCP target configured'},
  ],
};

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('a run parses the full envelope, failures included', () async {
    final pakka = PakkaApi(
      baseUrl: 'https://pakka.test',
      client: MockClient((req) async {
        expect(req.url.path, '/v1/runs');
        expect(jsonDecode(req.body)['mode'], 'live');
        return _json(_runBody);
      }),
    );
    final run = await pakka.run();
    expect(run.runId, '1204f48464ffec24');
    expect(run.results, hasLength(3));
    expect(run.results[0].checkId, 'dns.resolve');
    expect(run.results[0].timestamp, isNotNull);
    expect(run.results[2].outcome, 'fail');
    expect(run.results[2].summary, contains('outage'));
  });

  test('an investigation parses the finding and its slimmed results', () async {
    String? body;
    final pakka = PakkaApi(
      baseUrl: 'https://pakka.test',
      client: MockClient((req) async {
        expect(req.url.path, '/v1/investigations');
        body = req.body;
        return _json(_investigationBody);
      }),
    );
    final inv = await pakka.investigate(symptoms: 'cannot connect');
    expect(jsonDecode(body!)['symptoms'], 'cannot connect');
    expect(inv.finding.diagnosis, 'local-failure');
    expect(inv.finding.evidence, ['dns.resolve', 'tcp.connect']);
    expect(inv.finding.recommendedNext, contains('Switch Setup'));
    expect(inv.results, hasLength(2));
    expect(inv.results[1].outcome, 'skipped');
  });

  test('a harness failure reads as an ApiException with the server words', () async {
    final pakka = PakkaApi(
      baseUrl: 'https://pakka.test',
      client: MockClient((_) async => _json({'error': 'meta API key not configured'}, status: 503)),
    );
    final e = await pakka.investigate(symptoms: 'x').then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
    expect(e!.statusCode, 503);
    expect(e.fromServer, isTrue);
    // No code travels with it, so the UI words it by status, as the contract asks.
    final l = lookupAppLocalizations(const Locale('en'));
    expect(apiErrorText(l, e), l.errorServiceUnavailable);
  });

  test('a proxy outage that answers no JSON is generic, not a crash', () async {
    final pakka = PakkaApi(
      baseUrl: 'https://pakka.test',
      client: MockClient((_) async => http.Response('<html>bad gateway</html>', 502)),
    );
    await expectLater(pakka.ping(), throwsA(isA<ApiException>().having((e) => e.fromServer, 'fromServer', false)));
  });

  test('every call says which language the app is in', () async {
    final seen = <String?>[];
    final pakka = PakkaApi(
      baseUrl: 'https://pakka.test',
      client: MockClient((req) async {
        seen.add(req.headers['Accept-Language']);
        return _json({'status': 'ok'});
      }),
    )..language = 'pt-BR';
    await pakka.ping();
    expect(seen, ['pt-BR']);
  });

  test('diagnoses map to distinct states, and new words claim nothing', () {
    expect(diagnosisState('healthy'), RowState.ok);
    expect(diagnosisState('service-outage'), RowState.warn);
    expect(diagnosisState('local-failure'), RowState.bad);
    expect(diagnosisState('insufficient-evidence'), RowState.idle);
    expect(diagnosisState('brand-new'), RowState.idle);
    expect(outcomeState('pass'), RowState.ok);
    expect(outcomeState('fail'), RowState.bad);
    expect(outcomeState('error'), RowState.bad);
    expect(outcomeState('skipped'), RowState.idle);
    expect(outcomeState('brand-new'), RowState.idle);
  });

  test('unknown diagnoses and outcomes show the harness word', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(diagnosisText(l, 'local-failure'), l.pakkaDiagnosisLocalFailure);
    expect(diagnosisText(l, 'brand-new'), 'brand-new');
    expect(outcomeText(l, 'skipped'), l.pakkaOutcomeSkipped);
    expect(outcomeText(l, 'brand-new'), 'brand-new');
  });

  Future<void> pumpPakka(WidgetTester tester, MockClient client) async {
    await tester.pumpWidget(
      localizedApp(
        theme: openPakLight(),
        home: PakkaPage(pakka: PakkaApi(baseUrl: 'https://pakka.test', client: client)),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The page loads the service checks itself; the person only acts to
  // diagnose. A failing check must read as failed, not as missing.
  testWidgets('the checks load on open, failures shown as failures', (tester) async {
    await pumpPakka(tester, MockClient((_) async => _json(_runBody)));
    expect(find.text('Service checks'), findsOneWidget);
    expect(find.text('dns.resolve'), findsOneWidget);
    expect(find.text('http.health'), findsOneWidget);
    expect(find.text('Passed'), findsNWidgets(2));
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Diagnosis'), findsNothing); // nothing diagnosed yet
  });

  // The first vertical slice: describe the problem, read the diagnosis and
  // the evidence behind it.
  testWidgets('diagnosing renders the finding, the advice and the evidence', (tester) async {
    await pumpPakka(
      tester,
      MockClient((req) async => req.url.path == '/v1/investigations' ? _json(_investigationBody) : _json(_runBody)),
    );
    await tester.enterText(find.byType(TextField), 'cannot connect');
    await tester.tap(find.text('Diagnose'));
    await tester.pumpAndSettle();
    expect(find.text('A problem on your side'), findsOneWidget);
    expect(find.text('synthetic: local environment misconfigured'), findsOneWidget);
    expect(find.text('What to do next'), findsOneWidget);
    expect(find.text('synthetic: re-run Switch Setup and retest'), findsOneWidget);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
  });

  testWidgets('an unreachable harness explains itself on the checks', (tester) async {
    await pumpPakka(
      tester,
      MockClient((_) async => http.Response('Service Unavailable', 503)),
    );
    expect(find.text('Could not load. Pull down to try again.'), findsOneWidget);
    expect(find.textContaining('503'), findsOneWidget);
  });

  OpenPakApi catalogApi() => OpenPakApi(
    baseUrl: 'https://openpak.test',
    client: MockClient((_) async => _json({'items': []})),
  );

  // No Pakka endpoint in the build, no diagnostics entry on the tab: a
  // button that cannot work is worse than none.
  testWidgets('the Titles tab offers diagnostics only with a Pakka endpoint', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        theme: openPakLight(),
        home: TitlesPage(
          api: catalogApi(),
          pakka: PakkaApi(baseUrl: 'https://pakka.test', client: MockClient((_) async => _json(_runBody))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Diagnose a connection problem'), findsOneWidget);

    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: TitlesPage(api: catalogApi())));
    await tester.pumpAndSettle();
    expect(find.text('Diagnose a connection problem'), findsNothing);
  });

  testWidgets('the entry opens the diagnostics screen', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        theme: openPakLight(),
        home: TitlesPage(
          api: catalogApi(),
          pakka: PakkaApi(baseUrl: 'https://pakka.test', client: MockClient((_) async => _json(_runBody))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagnose a connection problem'));
    await tester.pumpAndSettle();
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('dns.resolve'), findsOneWidget);
  });
}

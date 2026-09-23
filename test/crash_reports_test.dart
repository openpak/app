import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/crash_reports.dart';

import 'localized.dart';

CrashReport report(String message, {String stack = '#0 main (a.dart:1)\n#1 run (b.dart:2)'}) =>
    CrashReport(message: message, stack: stack, time: DateTime.utc(2026, 9, 23, 12));

/// The multipart parts of a request, by field name.
Map<String, String> parts(http.Request req) {
  final boundary = req.headers['content-type']!.split('boundary=').last;
  final out = <String, String>{};
  for (final chunk in utf8.decode(req.bodyBytes).split('--$boundary')) {
    final name = RegExp(r'name="([^"]+)"').firstMatch(chunk)?.group(1);
    if (name == null) continue;
    final body = chunk.substring(chunk.indexOf('\r\n\r\n') + 4);
    out[name] = body.substring(0, body.length - 2); // the part's trailing CRLF
  }
  return out;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('the version constant is the one in pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(appVersion, line.split(':').last.trim().split('+').first);
  });

  test('the os reads as a person would write it', () {
    expect(osName('android', '15'), 'Android 15');
    expect(osName('ios', 'Version 18.0 (Build 22A3354)'), 'iOS 18.0');
    expect(osName('linux', '6.1'), 'Linux 6.1');
  });

  test('meta carries the contract fields, and only strings in fields', () {
    final r = CrashReport.from(ApiException(503, 'down', code: 'internal'), StackTrace.fromString('#0 a\n#1 b'));
    final meta = crashMeta(
      r,
      version: '0.9.0',
      device: const DeviceInfo(os: 'Android 15', fields: {'model': 'Google Pixel 8'}),
      locale: 'pt-BR',
    );
    expect(meta['source'], 'app');
    expect(meta['version'], '0.9.0');
    expect(meta['os'], 'Android 15');
    expect(meta['error_code'], 'internal');
    expect(meta['message'], 'down');
    final fields = meta['fields'] as Map<String, String>;
    expect(fields['model'], 'Google Pixel 8');
    expect(fields['locale'], 'pt-BR');
    expect(fields['error_type'], 'ApiException');
    expect(fields['stack_top'], '#0 a\n#1 b');
    // It survives the trip through JSON as the server reads it.
    expect(jsonDecode(jsonEncode(meta))['fields']['model'], 'Google Pixel 8');
  });

  test('no error code is sent for a plain exception', () {
    final meta = crashMeta(
      CrashReport.from(StateError('boom'), null),
      version: '0.9.0',
      device: const DeviceInfo(os: 'iOS 18.0'),
    );
    expect(meta.containsKey('error_code'), isFalse);
    expect((meta['fields'] as Map).containsKey('stack_top'), isFalse);
  });

  test('a long error is cut to size before it is saved', () {
    final r = CrashReport.from('x' * 100000, StackTrace.fromString('y' * 100000));
    expect(r.message.length, CrashReport.maxMessage);
    expect(r.stack.length, CrashReport.maxStack);
  });

  test('the queue keeps the newest few and the same error once', () {
    final q = CrashQueue();
    for (var i = 0; i < CrashQueue.capacity + 2; i++) {
      expect(q.add(report('error $i')), isTrue);
    }
    expect(q.reports.length, CrashQueue.capacity);
    expect(q.reports.first.message, 'error 2');
    expect(q.add(report('error 6')), isFalse);

    final back = CrashQueue.decode(q.encode());
    expect(back.reports.map((r) => r.message), q.reports.map((r) => r.message));
    expect(back.reports.first.time, DateTime.utc(2026, 9, 23, 12));
    expect(CrashQueue.decode('not json').reports, isEmpty);
    expect(CrashQueue.decode(null).reports, isEmpty);
  });

  test('a recorded error waits on the phone, and "never" records nothing', () async {
    final reporter = CrashReporter();
    var told = 0;
    reporter.onReport = () => told++;
    final stack = StackTrace.current;
    await reporter.record(StateError('one'), stack);
    await reporter.record(StateError('one'), stack);
    expect((await reporter.pending()).map((r) => r.message), ['Bad state: one']);
    expect(told, 1);

    await reporter.store.setConsent(CrashConsent.never);
    await reporter.record(StateError('two'), StackTrace.current);
    expect(await reporter.pending(), hasLength(1));
  });

  test('sending posts multipart meta and attachment with the bearer', () async {
    final seen = <http.Request>[];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_t',
      client: MockClient((req) async {
        seen.add(req);
        return http.Response('{"id":1}', 201);
      }),
    );
    final reporter = CrashReporter()..device = const DeviceInfo(os: 'Android 15');
    await reporter.record(StateError('boom'), StackTrace.fromString('#0 frame'));

    expect(await reporter.send(api, await reporter.pending()), 1);
    expect(await reporter.pending(), isEmpty);

    final req = seen.single;
    expect(req.url.path, '/api/v1/crash-reports');
    expect(req.headers['Authorization'], 'Bearer opk_t');
    final p = parts(req);
    final meta = jsonDecode(p['meta']!);
    expect(meta['source'], 'app');
    expect(meta['message'], 'Bad state: boom');
    expect(meta['version'], appVersion);
    expect(p['attachment'], contains('#0 frame'));
  });

  test('a report that fails to send stays, and a 401 does not sign out', () async {
    var signedOut = false;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_t',
      client: MockClient((_) async => http.Response('{"error":"unauthorized"}', 401)),
    )..onUnauthorized = () => signedOut = true;
    final reporter = CrashReporter();
    await reporter.record(StateError('boom'), null);
    expect(await reporter.send(api, await reporter.pending()), 0);
    expect(await reporter.pending(), hasLength(1));
    expect(signedOut, isFalse);
    expect(api.token, 'opk_t');
  });

  testWidgets('nothing is sent without a yes, and "Don\'t send" discards', (tester) async {
    var calls = 0;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      client: MockClient((_) async {
        calls++;
        return http.Response('', 201);
      }),
    );
    final reporter = CrashReporter();
    await reporter.record(StateError('boom'), null);

    await tester.pumpWidget(localizedApp(home: const Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(Scaffold));
    final done = offerCrashReports(context, reporter, api);
    await tester.pumpAndSettle();

    expect(find.text('OpenPak ran into a problem'), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.text("Don't send"));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await done;
    expect(await reporter.pending(), isEmpty);
  });

  testWidgets('"Always send" is remembered and sends', (tester) async {
    var calls = 0;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      client: MockClient((_) async {
        calls++;
        return http.Response('', 201);
      }),
    );
    final reporter = CrashReporter();
    await reporter.record(StateError('boom'), null);

    await tester.pumpWidget(localizedApp(home: const Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(Scaffold));
    final done = offerCrashReports(context, reporter, api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Always send'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(await reporter.store.consent(), CrashConsent.always);
    await done;
    expect(await reporter.pending(), isEmpty);
  });
}

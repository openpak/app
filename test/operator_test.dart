import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/open_url.dart';
import 'package:openpak/operator_page.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

Map<String, Object?> _info({
  bool inReview = false,
  List<Map<String, Object?>> apps = const [],
  List<Map<String, Object?>>? locations,
}) => {
  'available': true,
  'in_review': inReview,
  'roles': ['photon', 'turn', 'stun', 'npln_relay'],
  'max_servers': 2,
  'terms_url': 'https://openpak.org/operators',
  'requirements': {
    'node_cores': 8, 'node_ram_gb': 16, 'node_disk_gb': 160,
    'server_cores': 2, 'server_ram_gb': 4, 'server_bandwidth_mbps': 500, 'availability_pct': 99,
  },
  'locations': locations ?? [{'code': 'de-fra', 'country': 'DE', 'city': 'Frankfurt'}],
  'applications': apps,
};

void main() {
  late Map<String, Object?> info;
  late int infoStatus;
  late Map<String, Object?>? reject; // body for a 422 on writes
  late List<(String, String, Map<String, dynamic>)> writes;

  OpenPakApi api() => OpenPakApi(
    baseUrl: 'https://openpak.test',
    token: 't',
    client: MockClient((req) async {
      final path = req.url.path.replaceFirst('/api/v1', '');
      if (req.method == 'GET') {
        return infoStatus == 200
            ? _json(info)
            : _json({'error': 'applications are not available', 'code': 'operator_unavailable', 'available': false}, infoStatus);
      }
      writes.add((req.method, path, jsonDecode(req.body) as Map<String, dynamic>));
      if (reject != null) return _json(reject!, 422);
      return _json({'ok': true}, 201);
    }),
  );

  setUp(() {
    info = _info();
    infoStatus = 200;
    reject = null;
    writes = [];
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: OperatorPage(api: api())));
    await tester.pumpAndSettle();
  }

  test('parsing', () async {
    info = _info(apps: [
      {'id': 4, 'status': 'info', 'country': 'DE', 'city': 'Frankfurt', 'admin_note': 'Which provider?', 'servers': [
        {'cores': 4, 'ram_gb': 8, 'disk_gb': 200, 'disk_ssd': true, 'bandwidth_mbps': 1000, 'ipv6': true, 'roles': ['turn']},
      ]},
    ]);
    final o = await api().operatorInfo();
    expect(o.maxServers, 2);
    expect(o.requirements['node_cores'], 8);
    expect(o.locations.single.code, 'de-fra');
    expect(o.applications.single.servers.single.roles, ['turn']);
  });

  testWidgets('shows requirements, the form and the terms link opens the browser', (tester) async {
    final opened = <Uri>[];
    final old = openExternalUrl;
    openExternalUrl = (u) async => opened.add(u);
    addTearDown(() => openExternalUrl = old);
    await pump(tester);
    expect(find.textContaining('8 cores · 16 GB RAM · 160 GB NVMe/SSD'), findsOneWidget);
    expect(find.text('Send application'), findsOneWidget);
    await tester.tap(find.text('operator terms').first);
    expect(opened.single.toString(), 'https://openpak.org/operators');
  });

  testWidgets('503 shows applications unavailable calmly', (tester) async {
    infoStatus = 503;
    await pump(tester);
    expect(find.text('Applications are not available right now.'), findsOneWidget);
    expect(find.text('Could not load'), findsNothing);
  });

  testWidgets('in review: no new application, applications are listed', (tester) async {
    info = _info(inReview: true, apps: [
      {'id': 4, 'status': 'pending', 'country': 'DE', 'city': 'Frankfurt'},
    ]);
    await pump(tester);
    expect(find.text('In review'), findsOneWidget);
    expect(find.text('Send application'), findsNothing);
    expect(find.text('Join the waitlist'), findsNothing);
  });

  testWidgets('a question: shows the note and the reply is sent', (tester) async {
    info = _info(inReview: true, apps: [
      {'id': 4, 'status': 'info', 'country': 'DE', 'city': 'Frankfurt', 'admin_note': 'Which provider?'},
    ]);
    await pump(tester);
    expect(find.textContaining('Which provider?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Hetzner');
    await tester.tap(find.text('Send answer'));
    await tester.pumpAndSettle();
    expect(writes.single.$2, '/me/operator/reply');
    expect(writes.single.$3, {'id': 4, 'reply': 'Hetzner'});
  });

  testWidgets('rejected shows the reason', (tester) async {
    info = _info(apps: [
      {'id': 4, 'status': 'rejected', 'country': 'DE', 'city': 'Berlin', 'admin_note': 'Too small'},
    ]);
    await pump(tester);
    expect(find.text('Not accepted'), findsOneWidget);
    expect(find.textContaining('Reason: Too small'), findsOneWidget);
  });

  testWidgets('applying sends the servers, skips empty rows and lists 422 errors', (tester) async {
    await pump(tester);
    final submit = find.widgetWithText(FilledButton, 'Send application');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull); // no location, no terms
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frankfurt, DE').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'City'), 'Frankfurt');
    await tester.enterText(find.widgetWithText(TextField, 'Hosting provider'), 'Hetzner');
    await tester.enterText(find.widgetWithText(TextField, 'Contact email (operations and security)'), 'op@example.org');
    await tester.enterText(find.widgetWithText(TextField, 'CPU cores'), '8');
    await tester.enterText(find.widgetWithText(TextField, 'RAM (GB)'), '16');
    await tester.enterText(find.widgetWithText(TextField, 'Storage (GB)'), '200');
    await tester.enterText(find.widgetWithText(TextField, 'Bandwidth (Mbps, symmetric)'), '1000');
    await tester.tap(find.text('Add a server')); // a second row, left empty
    await tester.pumpAndSettle();
    await tester.tap(find.text('TURN relay').first);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    reject = {'error': 'x', 'code': 'invalid_application', 'errors': ['Server 1: needs at least 2 cores.', 'Accept the operator terms to apply.']};
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Server 1: needs at least 2 cores.'), findsOneWidget);
    expect(find.text('Accept the operator terms to apply.'), findsOneWidget);
    final body = writes.single.$3;
    expect(writes.single.$2, '/me/operator');
    expect(body['location'], 'de-fra');
    expect(body['terms'], true);
    expect((body['servers'] as List).length, 1);
    expect((body['servers'] as List).single, containsPair('roles', ['turn']));
    expect((body['servers'] as List).single, containsPair('bandwidth_mbps', 1000));
    // accepted: the form is reloaded
    reject = null;
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(writes.length, 2);
    expect(find.text('Server 1: needs at least 2 cores.'), findsNothing);
  });

  testWidgets('no open location: the waitlist form joins with an upper-case country', (tester) async {
    info = _info(locations: []);
    await pump(tester);
    expect(find.text('Send application'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Country (two letters)'), 'nz');
    await tester.enterText(find.widgetWithText(TextField, 'Contact email (operations and security)'), 'op@example.org');
    await tester.tap(find.widgetWithText(FilledButton, 'Join the waitlist'));
    await tester.pumpAndSettle();
    expect(writes.single.$2, '/me/operator/waitlist');
    expect(writes.single.$3, {'country': 'NZ', 'city': '', 'email': 'op@example.org'});
  });

  testWidgets('with open locations the waitlist is one tap away and back again', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Not listed? Join the waitlist'));
    await tester.tap(find.text('Not listed? Join the waitlist'));
    await tester.pumpAndSettle();
    expect(find.text('Send application'), findsNothing);
    await tester.ensureVisible(find.text('Back to the application'));
    await tester.tap(find.text('Back to the application'));
    await tester.pumpAndSettle();
    expect(find.text('Send application'), findsOneWidget);
  });

  testWidgets('German on a narrow phone does not overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    info = _info(apps: [
      {'id': 4, 'status': 'info', 'country': 'DE', 'city': 'Frankfurt', 'admin_note': 'Welcher Anbieter?'},
    ]);
    await tester.pumpWidget(localizedApp(theme: openPakLight(), locale: const Locale('de'), home: OperatorPage(api: api())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Region-Node betreiben'), findsNothing); // title is whatever the arb says; only overflow matters
  });
}

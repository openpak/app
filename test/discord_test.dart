import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/discord_row.dart';
import 'package:openpak/open_url.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

void main() {
  late Map<String, Object?> state;
  late int status;
  late List<String> calls;

  OpenPakApi api() => OpenPakApi(
    baseUrl: 'https://openpak.test',
    token: 't',
    client: MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.method == 'DELETE') {
        state = {'configured': true, 'linked': false};
        return http.Response('', 204);
      }
      return http.Response(jsonEncode(state), status, headers: {'content-type': 'application/json'});
    }),
  );

  setUp(() {
    state = {'configured': true, 'linked': false};
    status = 200;
    calls = [];
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: Scaffold(body: SingleChildScrollView(child: DiscordRow(api: api())))));
    await tester.pumpAndSettle();
  }

  testWidgets('hidden entirely while the server has no Discord credentials', (tester) async {
    state = {'configured': false, 'linked': false};
    await pump(tester);
    expect(find.text('Discord'), findsNothing);
  });

  testWidgets('hidden on any error', (tester) async {
    status = 500;
    await pump(tester);
    expect(find.text('Discord'), findsNothing);
  });

  testWidgets('not linked: the button opens the website in the browser', (tester) async {
    final opened = <Uri>[];
    final old = openExternalUrl;
    openExternalUrl = (u) async => opened.add(u);
    addTearDown(() => openExternalUrl = old);
    await pump(tester);
    expect(find.text('Link Discord'), findsOneWidget);
    expect(find.textContaining('Linking finishes in your browser'), findsOneWidget);
    await tester.tap(find.text('Link Discord'));
    expect(opened.single.toString(), 'https://openpak.test/account#devices');
  });

  testWidgets('linked: shows the name; Unlink asks first, then deletes', (tester) async {
    state = {'configured': true, 'linked': true, 'username': 'han#1'};
    await pump(tester);
    expect(find.text('han#1'), findsOneWidget);
    await tester.tap(find.text('Unlink'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('DELETE /api/v1/me/discord')));
    await tester.tap(find.widgetWithText(FilledButton, 'Unlink Discord'));
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /api/v1/me/discord'));
    expect(find.text('Link Discord'), findsOneWidget);
  });

  testWidgets('a linked account stays visible even if linking is no longer configured', (tester) async {
    state = {'configured': false, 'linked': true, 'username': 'han#1'};
    await pump(tester);
    expect(find.text('han#1'), findsOneWidget);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/account_details_page.dart';
import 'package:openpak/account_page.dart';
import 'package:openpak/api.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  final writes = <Map<String, dynamic>>[];
  var discord = <String, Object?>{'configured': true, 'linked': false};

  OpenPakApi api() => OpenPakApi(
    baseUrl: 'https://openpak.test',
    token: 't',
    client: MockClient((req) async {
      final path = req.url.path.replaceFirst('/api/v1', '');
      if (req.method == 'POST' && path == '/me/profile') writes.add(jsonDecode(req.body) as Map<String, dynamic>);
      return switch (path) {
        '/me' => _json({'account_id': 'a', 'display_name': 'Han', 'motto': 'Never tell me', 'bio': 'Smuggler', 'country': 'KR'}),
        '/me/discord' => _json(discord),
        '/me/sessions' => _json({'sessions': []}),
        '/me/friends' => _json({'friends': []}),
        '/me/friends/requests' => _json({'incoming': [], 'outgoing': []}),
        '/pakka/state' => _json({'available': false, 'eligible': false}),
        _ => _json({'saved': true}),
      };
    }),
  );

  setUp(() {
    writes.clear();
    discord = {'configured': true, 'linked': false};
  });

  testWidgets('the details page edits motto and bio and saves them alone', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final a = api();
    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: AccountDetailsPage(api: a, account: Account(id: 'a', displayName: 'Han', country: 'KR')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Never tell me'), findsOneWidget); // loaded from /me
    expect(find.text('Smuggler'), findsOneWidget);
    expect(find.text('South Korea'), findsOneWidget); // the website offers it
    await tester.enterText(find.widgetWithText(TextField, 'Motto'), 'Hi');
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();
    expect(writes.single, {'motto': 'Hi', 'bio': 'Smuggler'});
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('the Account page shows the Discord row in Linked platforms only when configured', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: AccountPage(api: api(), onSignedOut: () async {})));
    await tester.pumpAndSettle();
    expect(find.text('Link Discord'), findsOneWidget);

    discord = {'configured': false, 'linked': false};
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(localizedApp(theme: openPakDark(), home: AccountPage(api: api(), onSignedOut: () async {})));
    await tester.pumpAndSettle();
    expect(find.text('Link Discord'), findsNothing);
    expect(find.text('Discord'), findsNothing);
  });
}

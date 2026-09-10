import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/theme.dart';
import 'package:openpak/titles_page.dart';
import 'package:openpak/widgets.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

final _catalog = [
  CatalogItem(id: '1', kind: 'title', name: 'Outbound', console: 'Switch', status: 'live', votes: 3),
  CatalogItem(id: '2', kind: 'title', name: 'Splatoon 3', console: 'Switch', status: 'beta', votes: 9),
  CatalogItem(id: '3', kind: 'title', name: 'Xenoblade', console: 'Wii', status: 'requestable', votes: 1),
  CatalogItem(id: '4', kind: 'feature', name: 'Voice chat', status: 'planned', votes: 5),
];

void main() {
  test('fromJson tolerates a numeric or string id and fills defaults', () {
    expect(CatalogItem.fromJson({'id': 42, 'kind': 'title', 'name': 'A'}).id, '42');
    expect(CatalogItem.fromJson({'id': 'x', 'name': 'B'}).kind, 'title'); // defaulted
    final full = CatalogItem.fromJson({'id': '1', 'kind': 'feature', 'name': 'C', 'votes': 4, 'voted': true});
    expect(full.votes, 4);
    expect(full.voted, isTrue);
  });

  test('filter keeps one kind, and search/console narrow it', () {
    expect(filterCatalog(_catalog, kind: 'title'), hasLength(3));
    expect(filterCatalog(_catalog, kind: 'feature').single.name, 'Voice chat');
    expect(filterCatalog(_catalog, kind: 'title', search: 'spla').single.name, 'Splatoon 3');
    expect(filterCatalog(_catalog, kind: 'title', console: 'Wii').single.name, 'Xenoblade');
    expect(filterCatalog(_catalog, kind: 'title', status: 'live').single.name, 'Outbound');
  });

  test('byVotes is the scoreboard: most requested first', () {
    final ranked = filterCatalog(_catalog, kind: 'title', byVotes: true);
    expect(ranked.map((i) => i.name).toList(), ['Splatoon 3', 'Outbound', 'Xenoblade']);
    // Default keeps the server's catalog order (as given).
    final asIs = filterCatalog(_catalog, kind: 'title');
    expect(asIs.first.name, 'Outbound');
  });

  test('statusState maps the vocab to distinct row tints', () {
    expect(statusState('live'), RowState.ok);
    expect(statusState('beta'), RowState.warn);
    expect(statusState('not-feasible'), RowState.bad);
    expect(statusState('requestable'), RowState.idle);
    expect(statusLabel('not-feasible'), 'Not feasible');
  });

  Widget wrap(OpenPakApi api) =>
      MaterialApp(theme: openPakLight(), home: TitlesPage(api: api));

  testWidgets('signed out shows counts and the sign-in hint, no vote toggle', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test', // no token
      client: MockClient((_) async => _json({
            'items': [
              {'id': 1, 'kind': 'title', 'name': 'Outbound', 'console': 'Switch', 'status': 'live', 'votes': 3},
            ]
          })),
    );
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();
    expect(find.text('Outbound'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('Sign in to vote'), findsOneWidget);
  });

  testWidgets('signed in, tapping vote optimistically bumps the count', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/vote')) {
          return _json({'voted': true}); // server returns only the flag
        }
        return _json({
          'items': [
            {'id': 1, 'kind': 'title', 'name': 'Outbound', 'console': 'Switch', 'status': 'live', 'votes': 3, 'voted': false},
          ]
        });
      }),
    );
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
  });
}

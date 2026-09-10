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

  test('notStarted is requestable/planned only (alpha is started)', () {
    expect(notStarted('requestable'), isTrue);
    expect(notStarted('planned'), isTrue);
    expect(notStarted('alpha'), isFalse); // started: shows a pill, not a button
    expect(notStarted('live'), isFalse);
    expect(notStarted('beta'), isFalse);
    expect(notStarted('not-feasible'), isFalse);
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

  testWidgets('Request button shows only on not-started games; counts never', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      client: MockClient((_) async => _json({
            'items': [
              {'id': 1, 'kind': 'title', 'name': 'Outbound', 'console': 'Switch', 'status': 'live', 'votes': 3},
              {'id': 2, 'kind': 'title', 'name': 'Splatoon 3', 'console': 'Switch', 'status': 'beta', 'votes': 9},
              {'id': 5, 'kind': 'title', 'name': 'Fall Guys', 'console': 'Switch', 'status': 'alpha', 'votes': 7},
              {'id': 3, 'kind': 'title', 'name': 'Xenoblade', 'console': 'Wii', 'status': 'requestable', 'votes': 1},
            ]
          })),
    );
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();
    // Exactly one Request button — on the requestable title. Alpha/beta/live
    // show a pill, not a button.
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget); // alpha shows its pill
    // The internal vote counts are never rendered.
    expect(find.text('1'), findsNothing);
    expect(find.text('3'), findsNothing);
    expect(find.text('7'), findsNothing);
    expect(find.text('9'), findsNothing);
  });

  testWidgets('signed out shows a Request button and the sign-in hint, no count', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test', // no token
      client: MockClient((_) async => _json({
            'items': [
              {'id': 3, 'kind': 'title', 'name': 'Xenoblade', 'console': 'Wii', 'status': 'requestable', 'votes': 1},
            ]
          })),
    );
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('1'), findsNothing); // count is internal
    expect(find.textContaining('Sign in to request'), findsOneWidget);
    // Tapping does nothing (disabled): no crash, state unchanged.
    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    expect(find.text('Request'), findsOneWidget);
  });

  testWidgets('signed in, tapping Request flips it to Requested', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/vote')) {
          return _json({'id': 3, 'votes': 2, 'voted': true}); // fresh state
        }
        return _json({
          'items': [
            {'id': 3, 'kind': 'title', 'name': 'Xenoblade', 'console': 'Wii', 'status': 'requestable', 'votes': 1, 'voted': false},
          ]
        });
      }),
    );
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();
    expect(find.text('Request'), findsOneWidget);
    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    expect(find.text('Requested'), findsOneWidget);
    expect(find.text('2'), findsNothing); // count stays internal
  });

  testWidgets('the Network view is read-only — status matrix, no vote', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => _json({
            'items': [
              {'id': 3, 'kind': 'title', 'name': 'Xenoblade', 'status': 'requestable', 'votes': 1},
              {'id': 4, 'kind': 'feature', 'name': 'Voice chat', 'status': 'planned', 'notes': 'Not started.', 'votes': 5},
            ]
          })),
    );
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    expect(find.text('Voice chat'), findsOneWidget);
    expect(find.text('Not started.'), findsNothing); // single-line now: no verbose note
    expect(find.text('Request'), findsNothing); // features are never requestable
    expect(find.text('5'), findsNothing); // no count on the Network view
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/friends_page.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  testWidgets('a request can be declined beside Accept; a block is listed and undone', (tester) async {
    final posts = <String>[];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        if (req.method == 'POST') {
          posts.add('${req.url.path} ${req.body}');
          return _json({'message': 'ok'});
        }
        return switch (req.url.path) {
          '/api/v1/me/friends' => _json({'friends': []}),
          '/api/v1/me/friends/requests' => _json({
            'incoming': [
              {'account_id': 'acct-2', 'display_name': 'Lando', 'online': false},
            ],
            'outgoing': [],
          }),
          '/api/v1/me/blocked' => _json({
            'blocked': [
              {'account_id': 'acct-3', 'display_name': 'Boba', 'blocked_at': '2026-09-01T10:00:00Z'},
            ],
          }),
          _ => _json({}),
        };
      }),
    );
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: FriendsPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Accept'), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(posts.last, '/api/v1/me/friends/requests/decline {"account_id":"acct-2"}');

    expect(find.text('Boba'), findsOneWidget);
    expect(find.textContaining('Since '), findsOneWidget);
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    expect(posts.last, '/api/v1/me/friends/unblock {"account_id":"acct-3"}');
  });

  testWidgets('a failing block list does not take the friends down', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async => switch (req.url.path) {
            '/api/v1/me/friends' => _json({
              'friends': [
                {'account_id': 'b', 'display_name': 'Han', 'online': true},
              ],
            }),
            '/api/v1/me/friends/requests' => _json({'incoming': [], 'outgoing': []}),
            _ => http.Response('{"error":"nope"}', 502),
          }),
    );
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: FriendsPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Han'), findsOneWidget);
    expect(find.text('Unblock'), findsNothing);
  });

  testWidgets('a friend playing a cataloged game shows its name, never the title id', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async => switch (req.url.path) {
            '/api/v1/me/friends' => _json({
              'friends': [
                {
                  'account_id': 'f1',
                  'display_name': 'Leia',
                  'online': true,
                  'title_id': '0100ABCD00001000',
                  'namespace': 'switch',
                  'since': '2026-09-20T10:00:00Z',
                },
              ],
            }),
            '/api/v1/me/friends/requests' => _json({'incoming': [], 'outgoing': []}),
            '/api/v1/requests' => _json({
              'items': [
                {'id': '1', 'kind': 'title', 'name': 'Mario Kart 8 Deluxe', 'title_id': '0100ABCD00001000', 'console': 'Switch'},
              ],
            }),
            _ => _json({}),
          }),
    );
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: FriendsPage(api: api)));
    await tester.pumpAndSettle();

    // The pill names the game — the hex id never reaches the screen.
    expect(find.text('Mario Kart 8 Deluxe'), findsOneWidget);
    expect(find.textContaining('0100ABCD00001000'), findsNothing);

    // No overflow menu; the row's actions are tooltipped icon buttons.
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byTooltip('Message'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsOneWidget);
    expect(find.byTooltip('Block'), findsOneWidget);

    // Collapsed, the detail is not built yet; a tap on the row opens it.
    expect(find.textContaining('Online since'), findsNothing);
    await tester.tap(find.text('Leia'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nintendo Switch'), findsOneWidget);
    expect(find.textContaining('Online since'), findsOneWidget);
  });

  testWidgets('a game the catalog cannot name falls back to the platform, never the id', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async => switch (req.url.path) {
            '/api/v1/me/friends' => _json({
              'friends': [
                {
                  'account_id': 'f1',
                  'display_name': 'Han',
                  'online': true,
                  'title_id': '0100000000000000',
                  'namespace': 'wiiu',
                  'since': '2026-09-20T10:00:00Z',
                },
              ],
            }),
            '/api/v1/me/friends/requests' => _json({'incoming': [], 'outgoing': []}),
            _ => _json({}),
          }),
    );
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: FriendsPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('0100000000000000'), findsNothing);
    expect(find.textContaining('Wii U'), findsOneWidget);
    expect(find.textContaining('In a game'), findsOneWidget);
  });

  testWidgets('removing a friend is one tap on the icon button, then a confirmation', (tester) async {
    final posts = <String>[];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        if (req.method == 'POST') {
          posts.add(req.url.path);
          return _json({'message': 'ok'});
        }
        return switch (req.url.path) {
          '/api/v1/me/friends' => _json({
            'friends': [
              {'account_id': 'f1', 'display_name': 'Chewbacca', 'online': false},
            ],
          }),
          '/api/v1/me/friends/requests' => _json({'incoming': [], 'outgoing': []}),
          _ => _json({}),
        };
      }),
    );
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: FriendsPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(posts, contains('/api/v1/me/friends/remove'));
  });

  test('friendPlatformName spells out the console; an unknown namespace is capitalised', () {
    expect(friendPlatformName('switch'), 'Nintendo Switch');
    expect(friendPlatformName('wiiu'), 'Wii U');
    expect(friendPlatformName('3ds'), 'Nintendo 3DS');
    expect(friendPlatformName('citra'), 'Citra');
    expect(friendPlatformName(''), '');
  });

  test('looksLikeSwitchTitleId is exactly 16 hex digits, the only id /titles/icon can draw', () {
    expect(looksLikeSwitchTitleId('0100ABCD00001000'), isTrue);
    expect(looksLikeSwitchTitleId('0100abcd00001000'), isTrue);
    expect(looksLikeSwitchTitleId('RMCP01'), isFalse);
    expect(looksLikeSwitchTitleId(''), isFalse);
    expect(looksLikeSwitchTitleId('0100ABCD0000100'), isFalse); // 15 digits
  });
}

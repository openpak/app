import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/friends_page.dart';
import 'package:openpak/l10n.dart';
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

  test('friends parse avatar_url', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => _json({
            'friends': [
              {
                'account_id': 'f1',
                'display_name': 'Leia',
                'online': true,
                'avatar_url': '/media/avatars/f1/256',
              },
              {'account_id': 'f2', 'display_name': 'Han', 'online': false},
            ]
          })),
    );
    final friends = await api.friends();
    expect(friends, hasLength(2));
    expect(friends[0].avatarUrl, '/media/avatars/f1/256');
    expect(friends[1].avatarUrl, isNull);
  });

  test('friends parse where they play; absent or empty fields are null', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => _json({
            'friends': [
              {
                'account_id': 'f1',
                'display_name': 'Leia',
                'online': true,
                'title_id': '0100ABCD00001000',
                'namespace': 'switch',
                'since': '2026-09-20T10:00:00Z',
                'platform': 'switch',
                'client': 'ryujinx',
                'label': 'Ryujinx',
                'title_name': 'Mario Kart 8 Deluxe',
              },
              {
                'account_id': 'f2',
                'display_name': 'Han',
                'online': true,
                'platform': 'wiiu',
                'client': '',
                'label': 'Wii U',
                'title_name': '',
              },
              {'account_id': 'f3', 'display_name': 'Luke', 'online': true, 'title_id': 'x', 'namespace': '3ds'},
            ]
          })),
    );
    final friends = await api.friends();
    expect(friends[0].platform, 'switch');
    expect(friends[0].client, 'ryujinx');
    expect(friends[0].label, 'Ryujinx');
    expect(friends[0].titleName, 'Mario Kart 8 Deluxe');
    expect(friends[1].client, isNull);
    expect(friends[1].label, 'Wii U');
    expect(friends[1].titleName, isNull);
    expect(friends[2].platform, isNull);
    expect(friends[2].client, isNull);
    expect(friends[2].label, isNull);
    expect(friends[2].titleName, isNull);
  });

  group('friendPresenceText', () {
    final en = lookupAppLocalizations(const Locale('en'));
    Friend f({
      bool online = true,
      String? titleId,
      String? namespace,
      String? label,
      String? titleName,
      String? platform,
    }) =>
        Friend(
          accountId: 'a',
          displayName: 'A',
          online: online,
          titleId: titleId,
          namespace: namespace,
          label: label,
          titleName: titleName,
          platform: platform,
        );

    test('offline is unchanged, label or not', () {
      expect(friendPresenceText(en, f(online: false, label: 'Ryujinx')), 'Offline');
      expect(friendPresenceText(en, f(online: false)), 'Offline');
    });

    test('with a label: the game and where, or where alone', () {
      expect(
        friendPresenceText(en, f(titleId: '0100', label: 'Ryujinx', titleName: 'Mario Kart 8 Deluxe')),
        'Mario Kart 8 Deluxe on Ryujinx',
      );
      // The website has no name for it, the catalog does.
      expect(
        friendPresenceText(en, f(titleId: '0100', label: 'Eden'), catalogName: 'ARMS'),
        'ARMS on Eden',
      );
      expect(friendPresenceText(en, f(titleId: '0005', label: 'Cemu')), 'Playing on Cemu');
      expect(friendPresenceText(en, f(label: 'Switch')), 'Online on Switch');
      expect(friendPresenceText(en, f(titleId: '', label: '3DS')), 'Online on 3DS');
    });

    test('without a label (an older server) it is what the app always showed', () {
      expect(friendPresenceText(en, f(titleId: '0100', namespace: 'switch'), catalogName: 'ARMS'), 'ARMS');
      expect(friendPresenceText(en, f(titleId: '0100', namespace: 'wiiu')), 'Wii U · In a game');
      expect(friendPresenceText(en, f(titleId: '0100')), 'In a game');
      expect(friendPresenceText(en, f()), 'Online');
    });

    test('other languages word it too; the label is never translated', () {
      final de = lookupAppLocalizations(const Locale('de'));
      expect(friendPresenceText(de, f(label: 'Citron')), 'Online auf Citron');
      expect(friendPresenceText(de, f(titleId: '1', label: 'Azahar')), 'Spielt auf Azahar');
    });
  });

  testWidgets('a friend on an emulator: the pill says the game and the client; the detail has its chip', (tester) async {
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
                  'platform': 'switch',
                  'client': 'ryujinx',
                  'label': 'Ryujinx',
                  'title_name': 'Mario Kart 8 Deluxe',
                },
                {'account_id': 'f2', 'display_name': 'Han', 'online': true, 'platform': 'wiiu', 'client': 'cemu', 'label': 'Cemu'},
              ],
            }),
            '/api/v1/me/friends/requests' => _json({'incoming': [], 'outgoing': []}),
            _ => _json({}),
          }),
    );
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: FriendsPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Mario Kart 8 Deluxe on Ryujinx'), findsOneWidget);
    expect(find.text('Online on Cemu'), findsOneWidget);
    expect(find.byType(FriendClientChip), findsNothing);

    await tester.tap(find.text('Leia'));
    await tester.pumpAndSettle();
    expect(find.byType(FriendClientChip), findsOneWidget);
    expect(find.text('Ryujinx'), findsOneWidget);
    expect(find.text('Nintendo Switch'), findsOneWidget);
  });

  test('a typed code is fitted to its kind, as the website does', () {
    expect(fitFriendCode('openpak', 'op-ab2c-d3e4'), 'OP-AB2C-D3E4');
    expect(fitFriendCode('openpak', 'o1l2'), 'OP-2'); // 0/1/I/L/O/U are never in a code; the o is the prefix
    expect(fitFriendCode('switch', 'sw12345678abcd'), 'SW-1234-5678-ABCD');
    expect(fitFriendCode('switch', '1234-5678-9abc-def0-99'), 'SW-1234-5678-9ABC-DEF0');
    expect(fitFriendCode('3ds', '123456789012345'), '1234-5678-9012');
    expect(fitFriendCode('3ds', 'x'), '');
  });

  testWidgets('Add friend sends the code with its kind', (tester) async {
    final posts = <String>[];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        if (req.method == 'POST') posts.add('${req.url.path} ${req.body}');
        return switch (req.url.path) {
          '/api/v1/me/friends' => _json({'friends': []}),
          '/api/v1/me/friends/requests' => _json({'incoming': [], 'outgoing': []}),
          _ => _json({}),
        };
      }),
    );
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: FriendsPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add by friend code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenPak code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3DS friend code').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1111 2222 3333');
    await tester.pumpAndSettle();
    expect(find.text('1111-2222-3333'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(posts.last, '/api/v1/me/friends/requests {"friend_code":"1111-2222-3333","kind":"3ds"}');
  });
}

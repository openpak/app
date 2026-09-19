import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/friends_page.dart';
import 'package:openpak/theme.dart';

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
    await tester.pumpWidget(MaterialApp(theme: openPakLight(), home: FriendsPage(api: api)));
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
    await tester.pumpWidget(MaterialApp(theme: openPakLight(), home: FriendsPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Han'), findsOneWidget);
    expect(find.text('Unblock'), findsNothing);
  });
}

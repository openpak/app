import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/saves_page.dart';
import 'package:openpak/theme.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  test('platformConsole names the console behind an emulator', () {
    expect(platformConsole('citron'), 'Switch');
    expect(platformConsole('Wii'), 'Wii');
    expect(platformConsole('ps2'), 'ps2');
  });

  testWidgets('the website order: usage, the saves by game, then storage; the filter narrows', (tester) async {
    final calls = <String>[];
    final api = OpenPakApi(
      baseUrl: 'http://x',
      token: 't',
      client: MockClient((req) async {
        if (req.method != 'GET') {
          calls.add('${req.method} ${req.url.path}');
          return http.Response('', 204);
        }
        return switch (req.url.path) {
          '/api/v1/me/saves' => _json({
            'saves': [
              for (final (p, id) in [('citron', '0100ABCD00001000'), ('wii', 'RMCP01')])
                {
                  'platform': p,
                  'title_id': id,
                  if (p == 'citron') 'name': 'Mario Kart 8 Deluxe',
                  if (p == 'citron') 'icon': '/titles/icon/$id',
                  'versions': [
                    {'id': 1, 'number': 2, 'size': 2048, 'conflict': p == 'wii', 'created_at': '2026-09-01T10:00:00Z'},
                    {'id': 9, 'number': 1, 'size': 1024, 'created_at': '2026-08-01T10:00:00Z'},
                  ],
                },
            ],
            'usage': {'allowance_used': 950, 'allowance': 1000},
          }),
          '/api/v1/me/saves/storage/kinds' => _json({'s3': true}),
          _ => _json({'connected': false}),
        };
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: openPakLight(),
        home: SavesPage(api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('95%'), findsOneWidget);
    expect(find.text('Showing 2 / 2'), findsOneWidget);
    expect(find.text('Conflict'), findsOneWidget);
    expect(find.text('Mario Kart 8 Deluxe'), findsOneWidget);
    expect(find.text('RMCP01'), findsOneWidget); // no name: the id

    // Picking an older version restores it; delete asks first, then acts on the current one.
    await tester.tap(find.textContaining('Version 2').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Version 1').last);
    await tester.pumpAndSettle();
    expect(calls, ['POST /api/v1/me/saves/versions/9/restore']);
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.delete_outline).first).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(calls.last, 'DELETE /api/v1/me/saves/versions/1');

    await tester.enterText(find.byType(TextField), 'rmc');
    await tester.pump();
    expect(find.text('Showing 1 / 2'), findsOneWidget);
    expect(find.text('Mario Kart 8 Deluxe'), findsNothing);
  });
}

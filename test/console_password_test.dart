import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/console_password_row.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

void main() {
  test('the console password calls', () async {
    final seen = <String>[];
    Map<String, Object?>? body;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        seen.add('${req.method} ${req.url.path}');
        if (req.method == 'POST') {
          body = jsonDecode(req.body) as Map<String, Object?>;
          return http.Response(jsonEncode({'ok': true, 'nnid': 'tobagin'}), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode({'nnid': 'tobagin', 'pid': 1, 'mode': 'sync', 'min': 6, 'max': 16}), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    final info = await api.consolePassword();
    expect(info!.nnid, 'tobagin');
    expect(info.mode, 'sync');
    await api.setConsolePassword('current-pw', 'console-pw', code: '123456');
    expect(seen, ['GET /api/v1/me/wiiu/console-password', 'POST /api/v1/me/wiiu/console-password']);
    expect(body, {'current_password': 'current-pw', 'console_password': 'console-pw', 'code': '123456'});
  });

  test('no Wii U ID yet reads as nothing to show', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async => http.Response('{}', 404)),
    );
    expect(await api.consolePassword(), isNull);
  });

  testWidgets('the row names the ID to type and says the OpenPak password is the console password', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async => http.Response(
          jsonEncode({'nnid': 'tobagin', 'pid': 1, 'mode': 'sync', 'min': 6, 'max': 16}), 200,
          headers: {'content-type': 'application/json'})),
    );
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: Scaffold(body: ConsolePasswordRow(api: api))));
    await tester.pumpAndSettle();
    expect(find.textContaining('tobagin'), findsOneWidget);
    expect(find.textContaining('your OpenPak password'), findsOneWidget);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';

http.Response json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {
      'content-type': 'application/json',
    });

void main() {
  test('signing in keeps the bearer and sends it afterwards', () async {
    String? seenAuth;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      client: MockClient((req) async {
        if (req.url.path == '/api/v1/token') {
          expect(jsonDecode(req.body)['email'], 'a@x.test');
          return json({'token': 'opk_abc', 'token_type': 'Bearer'}, status: 201);
        }
        seenAuth = req.headers['Authorization'];
        return json({'account_id': 'acct-1', 'display_name': 'Leia'});
      }),
    );

    await api.signIn('a@x.test', 'password-1');
    expect(api.token, 'opk_abc');
    final me = await api.me();
    expect(me.displayName, 'Leia');
    expect(seenAuth, 'Bearer opk_abc');
  });

  test('a dead token is reported as unauthorized, not as a generic failure',
      () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_dead',
      client: MockClient((_) async => json({'error': 'unauthorized'}, status: 401)),
    );
    // The UI signs out on exactly this, so the distinction has to survive.
    await expectLater(
      api.friends(),
      throwsA(isA<ApiException>().having((e) => e.unauthorized, 'unauthorized', true)),
    );
  });

  test('friends carry presence, and offline friends stay in the list', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => json({
            'friends': [
              {
                'account_id': 'b',
                'display_name': 'Han',
                'online': true,
                'title_id': '0100E65002BB8000',
                'namespace': 'switch',
                'since': '2026-09-08T09:15:00Z',
              },
              {'account_id': 'c', 'display_name': 'Chewie', 'online': false},
            ]
          })),
    );
    final friends = await api.friends();
    expect(friends, hasLength(2));
    expect(friends[0].online, isTrue);
    expect(friends[0].titleId, '0100E65002BB8000');
    expect(friends[0].since, isNotNull);
    expect(friends[1].online, isFalse);
    expect(friends[1].titleId, isNull);
  });

  test('invitations parse, and an elapsed expiry reads as expired', () async {
    final past = DateTime.now().subtract(const Duration(minutes: 5)).toUtc();
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => json({
            'invitations': [
              {
                'invitation_id': 'inv-1',
                'from': 'Han',
                'title_id': '0100E65002BB8000',
                'namespace': 'switch',
                'expires_at': past.toIso8601String(),
              }
            ]
          })),
    );
    final inv = (await api.invitations()).single;
    expect(inv.id, 'inv-1');
    expect(inv.from, 'Han');
    expect(inv.expired, isTrue);
  });

  test('declining something already gone is false, not an error', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => json({'declined': false})),
    );
    expect(await api.decline('inv-1'), isFalse);
  });

  test('a non-JSON error body still yields a usable message', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => http.Response('<html>502</html>', 502)),
    );
    // A proxy outage must not surface as a JSON parse crash.
    await expectLater(
      api.me(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 502)),
    );
  });
}

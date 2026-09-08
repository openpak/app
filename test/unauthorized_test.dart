import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';

void main() {
  test('a rejected bearer signs out once, from wherever it was rejected', () {
    var signedOut = 0;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_dead',
      client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'invalid or expired token'}),
            401,
          )),
    )..onUnauthorized = () => signedOut++;

    expect(api.me(), throwsA(isA<ApiException>()));
    return Future<void>.delayed(Duration.zero, () {
      expect(signedOut, 1, reason: 'the app must return to the sign-in form');
      expect(api.token, isNull, reason: 'a dead token is not worth keeping');
    });
  });

  test('a 503 leaves the bearer alone', () async {
    var signedOut = 0;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_live',
      client: MockClient((_) async => http.Response('{"error":"try again"}', 503)),
    )..onUnauthorized = () => signedOut++;

    await expectLater(api.me(), throwsA(isA<ApiException>()));
    expect(signedOut, 0);
    expect(api.token, 'opk_live', reason: 'an outage is not a sign-out');
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/sign_in_page.dart';

import 'localized.dart';

void main() {
  Future<void> pumpSignIn(WidgetTester tester, MockClient client) async {
    await tester.pumpWidget(
      localizedApp(
        home: SignInPage(
          api: OpenPakApi(baseUrl: 'https://openpak.test', client: client),
          onSignedIn: (_) async {},
        ),
      ),
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'a@x.test');
    await tester.enterText(find.byType(TextField).last, 'password-1');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
  }

  // Wrong credentials are the most common thing that happens on this screen,
  // and the message has to say so rather than showing a status code.
  testWidgets('bad credentials explain themselves', (tester) async {
    await pumpSignIn(
      tester,
      MockClient((_) async => http.Response(jsonEncode({'error': 'unauthorized'}), 401,
          headers: {'content-type': 'application/json'})),
    );
    await submit(tester);
    expect(find.textContaining('do not match'), findsOneWidget);
  });

  // Being rate limited is not the same as being wrong, and telling someone
  // their password is wrong when it is not sends them to reset it.
  testWidgets('rate limiting says to wait, not that the password is wrong',
      (tester) async {
    await pumpSignIn(
      tester,
      MockClient((_) async => http.Response('{}', 429,
          headers: {'content-type': 'application/json'})),
    );
    await submit(tester);
    expect(find.textContaining('Wait a minute'), findsOneWidget);
  });

  testWidgets('an unreachable server does not look like a rejection',
      (tester) async {
    await pumpSignIn(tester, MockClient((_) async => throw const SocketishError()));
    await submit(tester);
    expect(find.textContaining('Check your connection'), findsOneWidget);
  });

  /// POST /token answers with a challenge; /token/2fa answers [second].
  MockClient twoFactor(http.Response Function() second, {List<String>? sent}) =>
      MockClient((req) async {
        sent?.add('${req.url.path} ${req.body}');
        if (req.url.path == '/api/v1/token') {
          return http.Response(jsonEncode({'two_factor_required': true, 'challenge': 'ch-1'}), 202,
              headers: {'content-type': 'application/json'});
        }
        return second();
      });

  testWidgets('a two-factor account asks for a code, then signs in', (tester) async {
    String? token;
    final sent = <String>[];
    await tester.pumpWidget(
      localizedApp(
        home: SignInPage(
          api: OpenPakApi(
            baseUrl: 'https://openpak.test',
            client: twoFactor(
              () => http.Response(jsonEncode({'token': 'opk_2fa'}), 201,
                  headers: {'content-type': 'application/json'}),
              sent: sent,
            ),
          ),
          onSignedIn: (t) async => token = t,
        ),
      ),
    );
    await submit(tester);
    expect(find.text('Enter your code'), findsOneWidget);
    expect(token, isNull);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(token, 'opk_2fa');
    expect(sent.last, '/api/v1/token/2fa {"challenge":"ch-1","code":"123456"}');
  });

  // A wrong code and a spent challenge are the same 401; a spent challenge
  // cannot be retried, so the page starts over from the password.
  testWidgets('a rejected code goes back to the password', (tester) async {
    await pumpSignIn(
      tester,
      twoFactor(() => http.Response(jsonEncode({'error': 'invalid code'}), 401,
          headers: {'content-type': 'application/json'})),
    );
    await submit(tester);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your code'), findsNothing);
    expect(find.textContaining('Sign in again'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('a locked second factor says how long to wait', (tester) async {
    await pumpSignIn(
      tester,
      twoFactor(() => http.Response(jsonEncode({'error': 'locked'}), 429,
          headers: {'content-type': 'application/json'})),
    );
    await submit(tester);
    await tester.enterText(find.byType(TextField), 'abcde-fghij');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('15 minutes'), findsOneWidget);
    expect(find.text('Enter your code'), findsOneWidget);
  });

  test('the minimum age counts whole years, 29 February rolling to 1 March', () {
    expect(underMinimumAge(DateTime(2010, 10, 24), DateTime(2026, 10, 23)), isTrue);
    expect(underMinimumAge(DateTime(2010, 10, 23), DateTime(2026, 10, 23)), isFalse);
    expect(underMinimumAge(DateTime(2008, 2, 29), DateTime(2024, 2, 28)), isTrue);
    expect(underMinimumAge(DateTime(2008, 2, 29), DateTime(2024, 2, 29)), isFalse);
    expect(isoDay(DateTime(2008, 3, 5)), '2008-03-05');
  });

  testWidgets('creating an account waits for a date of birth', (tester) async {
    await pumpSignIn(tester, MockClient((_) async => http.Response('{}', 500)));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your date of birth'), findsOneWidget);
    final create = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'));
    expect(create.onPressed, isNull);
  });
}

/// A stand-in for any transport failure; the page must not read it as a
/// credential problem.
class SocketishError implements Exception {
  const SocketishError();
}

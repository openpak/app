import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/sign_in_page.dart';

void main() {
  Future<void> pumpSignIn(WidgetTester tester, MockClient client) async {
    await tester.pumpWidget(
      MaterialApp(
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
}

/// A stand-in for any transport failure; the page must not read it as a
/// credential problem.
class SocketishError implements Exception {
  const SocketishError();
}

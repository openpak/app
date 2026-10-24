import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/l10n.dart';
import 'package:openpak/sign_in_page.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

http.Response json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

final en = lookupAppLocalizations(const Locale('en'));

void main() {
  group('Turnstile', () {
    /// The server: /auth/config says [enabled]; /password/forgot answers [forgot].
    MockClient server(bool enabled, List<String> sent, {http.Response Function()? forgot}) => MockClient((req) async {
      sent.add('${req.method} ${req.url.path} ${req.body}');
      if (req.url.path == '/api/v1/auth/config') {
        return json({
          'turnstile': enabled
              ? {'enabled': true, 'site_key': 'k', 'widget_path': '/turnstile-widget'}
              : {'enabled': false},
        }, 200);
      }
      return forgot?.call() ?? json({'message': 'ok'}, 202);
    });

    Future<void> forgot(WidgetTester tester, MockClient client, {String? answer, List<Uri>? asked}) async {
      await tester.pumpWidget(
        localizedApp(
          theme: openPakLight(),
          home: SignInPage(
            api: OpenPakApi(baseUrl: 'https://openpak.test', client: client),
            onSignedIn: (_) async {},
            solveTurnstile: (context, {required widget, required websitePage, language}) async {
              asked?.addAll([widget, websitePage]);
              return answer;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'a@x.test');
      await tester.tap(find.text(en.signInForgot));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.commonSend));
      await tester.pumpAndSettle();
    }

    testWidgets('the reset mail sends the answer from the widget page on this site', (tester) async {
      final sent = <String>[];
      final asked = <Uri>[];
      await forgot(tester, server(true, sent), answer: 'tok-1', asked: asked);
      expect(asked, [
        Uri.parse('https://openpak.test/turnstile-widget'),
        Uri.parse('https://openpak.test/forgot-password'),
      ]);
      expect(sent.last, 'POST /api/v1/password/forgot {"email":"a@x.test","turnstile_token":"tok-1"}');
      expect(find.text(en.signInResetSent), findsOneWidget);
    });

    testWidgets('cancelling the check sends nothing', (tester) async {
      final sent = <String>[];
      await forgot(tester, server(true, sent));
      expect(sent.where((s) => s.contains('/password/forgot')), isEmpty);
    });

    testWidgets('without Turnstile the form goes as before', (tester) async {
      final sent = <String>[];
      await forgot(tester, server(false, sent), answer: 'never-asked');
      expect(sent.last, 'POST /api/v1/password/forgot {"email":"a@x.test"}');
    });

    testWidgets('a refused answer is said in the app language', (tester) async {
      final sent = <String>[];
      await forgot(
        tester,
        server(
          true,
          sent,
          forgot: () => json({'error': 'the human check did not pass; try again', 'code': 'turnstile_failed'}, 400),
        ),
        answer: 'tok-1',
      );
      expect(find.text(en.errorTurnstileFailed), findsOneWidget);
    });

    test('signup sends the token; an older server without /auth/config asks for none', () async {
      final sent = <String>[];
      final api = OpenPakApi(
        baseUrl: 'https://openpak.test',
        client: MockClient((req) async {
          sent.add(req.body);
          return req.url.path == '/api/v1/auth/config' ? http.Response('not found', 404) : json({}, 202);
        }),
      );
      expect((await api.authConfig()).turnstile, isFalse);
      await api.register(
        email: 'e',
        password: 'p',
        displayName: 'd',
        handle: 'h',
        birthday: '1990-01-01',
        turnstileToken: 't',
      );
      expect(jsonDecode(sent.last)['turnstile_token'], 't');
      expect(apiErrorText(en, ApiException(503, 'x', code: 'turnstile_unavailable')), en.errorTurnstileUnavailable);
    });
  });

  group('restore', () {
    /// POST /token answers 409 deletion pending; /token/restore answers [restore].
    MockClient server(List<String> sent, http.Response Function() restore) => MockClient((req) async {
      sent.add(req.url.path);
      if (req.url.path == '/api/v1/token') {
        return json({
          'error': 'this account is closed',
          'code': 'account_deletion_pending',
          'deletion_pending': true,
          'erase_after': '2026-11-22T12:00:00Z',
        }, 409);
      }
      if (req.url.path == '/api/v1/token/restore') return restore();
      return json({'token': 'opk_2fa'}, 201);
    });

    Future<void> signIn(WidgetTester tester, MockClient client, void Function(String) signedIn) async {
      await tester.pumpWidget(
        localizedApp(
          theme: openPakLight(),
          home: SignInPage(
            api: OpenPakApi(baseUrl: 'https://openpak.test', client: client),
            onSignedIn: (t) async => signedIn(t),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'a@x.test');
      await tester.enterText(find.byType(TextField).last, 'password-1');
      await tester.tap(find.text(en.signInButton));
      await tester.pumpAndSettle();
    }

    testWidgets('a deleted account offers the restore with its date, and Restore signs in', (tester) async {
      final sent = <String>[];
      String? token;
      await signIn(tester, server(sent, () => json({'token': 'opk_back'}, 201)), (t) => token = t);
      expect(find.text(en.restoreBody(shortDate(en, DateTime.utc(2026, 11, 22, 12)))), findsOneWidget);
      expect(token, isNull);
      await tester.tap(find.byKey(const Key('restore-account')));
      await tester.pumpAndSettle();
      expect(sent.last, '/api/v1/token/restore');
      expect(token, 'opk_back');
    });

    testWidgets('Cancel leaves the account deleted', (tester) async {
      final sent = <String>[];
      await signIn(tester, server(sent, () => json({'token': 'x'}, 201)), (_) {});
      await tester.tap(find.text(en.commonCancel));
      await tester.pumpAndSettle();
      expect(sent, ['/api/v1/token']);
      expect(find.text(en.restoreTitle), findsNothing);
      expect(find.text(en.commonPassword), findsOneWidget);
    });

    testWidgets('a two-factor account still needs its code after the restore', (tester) async {
      final sent = <String>[];
      String? token;
      await signIn(
        tester,
        server(sent, () => json({'two_factor_required': true, 'challenge': 'ch-1'}, 202)),
        (t) => token = t,
      );
      await tester.tap(find.byKey(const Key('restore-account')));
      await tester.pumpAndSettle();
      expect(find.text(en.signInCodeTitle), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text(en.signInButton));
      await tester.pumpAndSettle();
      expect(sent.last, '/api/v1/token/2fa');
      expect(token, 'opk_2fa');
    });

    testWidgets('a grace period that is over says so', (tester) async {
      await signIn(
        tester,
        server([], () => json({'error': 'the grace period is over', 'code': 'account_erasure_started'}, 410)),
        (_) {},
      );
      await tester.tap(find.byKey(const Key('restore-account')));
      await tester.pumpAndSettle();
      expect(find.text(en.errorAccountErasureStarted), findsOneWidget);
    });
  });
}

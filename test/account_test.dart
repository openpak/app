import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/account_page.dart';
import 'package:openpak/api.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  late List<String> writes;
  late Map<String, dynamic> me;

  OpenPakApi api() => OpenPakApi(
        baseUrl: 'https://openpak.test',
        token: 't',
        client: MockClient((req) async {
          if (req.method != 'GET') writes.add('${req.method} ${req.url.path} ${req.body}');
          return switch (req.url.path) {
            '/api/v1/me' when req.method == 'GET' => _json(me),
            '/api/v1/me/sessions' => _json({'sessions': []}),
            '/api/v1/me/2fa/setup' => _json({
              'secret': 'JBSWY3DPEHPK3PXP',
              'otpauth_uri': 'otpauth://totp/OpenPak:a?secret=JBSWY3DPEHPK3PXP&issuer=OpenPak',
            }),
            '/api/v1/me/2fa/enable' => _json({'recovery_codes': List.generate(10, (i) => 'rc-$i')}),
            _ => _json({'message': 'ok'}),
          };
        }),
      );

  Future<void> pump(WidgetTester tester, OpenPakApi api, {Future<void> Function()? onSignedOut}) async {
    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: AccountPage(api: api, onSignedOut: onSignedOut ?? () async {}),
    ));
    await tester.pumpAndSettle();
  }

  // A ListView builds past the screen edge, so "found" is not "on screen":
  // ensureVisible then brings it into the viewport before a tap.
  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  setUp(() {
    writes = [];
    me = {'account_id': 'a', 'display_name': 'Leia', 'email_verified': false, 'two_factor_enabled': false};
  });

  testWidgets('an unconfirmed address offers the link again; an email change asks for the password', (tester) async {
    await pump(tester, api());
    await scrollTo(tester, find.text('Change email'));
    expect(find.text('Not confirmed'), findsOneWidget);
    await tester.tap(find.text('Send the link again'));
    await tester.pumpAndSettle();
    expect(writes.last, 'POST /api/v1/me/verify/resend {}');

    await scrollTo(tester, find.text('Change email')); // the reload scrolled back up
    await tester.tap(find.text('Change email'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'new@x.test');
    await tester.enterText(find.byType(TextField).last, 'pw-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Change email'));
    await tester.pumpAndSettle();
    expect(writes.last, 'POST /api/v1/me/email {"new_email":"new@x.test","password":"pw-1"}');
  });

  testWidgets('two-factor setup warns about consoles, then shows the recovery codes once', (tester) async {
    await pump(tester, api());
    await scrollTo(tester, find.text('Set up'));
    await tester.tap(find.text('Set up'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Switch, Wii U and 3DS'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'pw-1');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
    expect(find.textContaining('Switch, Wii U and 3DS'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Turn on two-factor'));
    await tester.pumpAndSettle();
    expect(writes.last, 'POST /api/v1/me/2fa/enable {"code":"123456"}');
    expect(find.textContaining('rc-9'), findsOneWidget);

    me['two_factor_enabled'] = true;
    await scrollTo(tester, find.text('I have saved them'));
    await tester.tap(find.text('I have saved them'));
    await tester.pumpAndSettle();
    expect(find.text('Turn off'), findsOneWidget);
  });

  testWidgets('deleting asks first, sends the password and code, then signs out', (tester) async {
    me['two_factor_enabled'] = true;
    var signedOut = false;
    await pump(tester, api(), onSignedOut: () async => signedOut = true);
    await scrollTo(tester, find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'pw-1');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    expect(writes.last, 'DELETE /api/v1/me {"password":"pw-1","code":"123456"}');
    expect(signedOut, isTrue);
  });

  testWidgets('cancelling the first question deletes nothing', (tester) async {
    await pump(tester, api());
    await scrollTo(tester, find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/chat_page.dart';
import 'package:openpak/l10n.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  test('an error code is shown in the app language, not the server English', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'wrong password', 'code': 'wrong_password'}),
            403,
          )),
    );
    final e = await api.changePassword('a', 'b').then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
    expect(e!.code, 'wrong_password');
    expect(apiErrorText(en, e), en.errorWrongPassword);
    // No code (an older server): worded by status; a code nobody knows yet, too.
    expect(apiErrorText(en, ApiException(429, 'rate limited')), en.errorRateLimited);
    // The signup age check has no code of its own; its words are read.
    expect(
      apiErrorText(en, ApiException(400, 'you must be at least 16 to create an OpenPak account', fromServer: true)),
      en.signInTooYoung(16),
    );
    expect(
      apiErrorText(en, ApiException(400, 'birthday must be a past date, YYYY-MM-DD', fromServer: true)),
      en.errorBirthdayInvalid,
    );
    expect(apiErrorText(en, ApiException(500, 'x', code: 'brand_new')), en.errorGeneric(500));
  });

  test('every call says which language the app is in', () async {
    final seen = <String?>[];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      client: MockClient((req) async {
        seen.add(req.headers['Accept-Language']);
        return http.Response(jsonEncode({'token': 'opk_x'}), 201);
      }),
    )..language = 'pt-BR';
    await api.signIn('a@x.test', 'pw');
    await api.news();
    expect(seen, ['pt-BR', 'pt-BR']);
  });

  test('a message that is not text is worded by its kind', () {
    final m = ChatMessage(id: 1, from: 'a', kind: 'invite', body: '', sentAt: DateTime(2026));
    expect(chatLine(en, m), '[Invite message]');
  });
}

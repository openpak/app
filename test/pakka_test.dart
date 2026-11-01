import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/account_page.dart';
import 'package:openpak/api.dart';
import 'package:openpak/pakka_page.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

String _sse(String event, Map<String, Object?> data) => 'event: $event\ndata: ${jsonEncode(data)}\n\n';

/// A stand-in for the Pakka endpoints of the server.
class _Fake {
  Map<String, Object?> state = {'available': true, 'eligible': true, 'consent': true, 'notice_version': '1'};
  List<Map<String, Object?>> conversations = [];
  StreamController<List<int>>? stream; // the reply being written
  int sendStatus = 200;
  final calls = <String>[];

  OpenPakApi get api => OpenPakApi(
    baseUrl: 'https://openpak.test',
    token: 't',
    client: MockClient.streaming((req, body) async {
      final path = req.url.path.replaceFirst('/api/v1/pakka', '');
      calls.add('${req.method} $path');
      http.StreamedResponse json(Object o, [int code = 200]) => http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(o))),
        code,
        headers: {'content-type': 'application/json'},
      );
      if (path == '/state') return json(state);
      if (path == '/consent') {
        state = {...state, 'consent': req.method == 'POST'};
        return json({});
      }
      if (path == '/conversations' && req.method == 'GET') return json({'conversations': conversations});
      if (path == '/conversations') return json({'id': 'c1', 'title': ''}, 201);
      if (path.endsWith('/messages')) {
        if (sendStatus != 200) return json({'error': 'busy', 'code': 'busy'}, sendStatus);
        stream = StreamController<List<int>>();
        return http.StreamedResponse(stream!.stream, 200, headers: {'content-type': 'text/event-stream'});
      }
      if (req.method == 'DELETE') {
        conversations.removeWhere((c) => path.endsWith('/${c['id']}'));
        return json({});
      }
      return json({'id': 'c1', 'messages': []});
    }),
  );
}

void main() {
  late _Fake fake;
  setUp(() => fake = _Fake());

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: home));
    await tester.pumpAndSettle();
  }

  bool inputEnabled(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).enabled ?? true;

  testWidgets('chat is blocked until the data-use notice is accepted', (tester) async {
    fake.state = {...fake.state, 'consent': false};
    await pump(tester, PakkaPage(api: fake.api));
    expect(find.text('Before you chat with Pakka'), findsOneWidget);
    expect(inputEnabled(tester), isFalse);
    await tester.tap(find.text('I understand, start chatting'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('POST /consent'));
    expect(inputEnabled(tester), isTrue);
    expect(find.text('Before you chat with Pakka'), findsNothing);
  });

  testWidgets('withdrawing from the notice blocks the chat again', (tester) async {
    await pump(tester, PakkaPage(api: fake.api));
    await tester.tap(find.byTooltip('Data use'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Withdraw and stop chatting'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('DELETE /consent'));
    expect(inputEnabled(tester), isFalse);
  });

  testWidgets('an ineligible account sees no entry and the page says so', (tester) async {
    fake.state = {...fake.state, 'eligible': false};
    await pump(tester, AccountPage(api: fake.api, onSignedOut: () async {}));
    expect(find.text('Pakka'), findsNothing);
    await pump(tester, PakkaPage(api: fake.api));
    expect(find.text("Pakka isn't available on this account"), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('an eligible account sees the entry in Account', (tester) async {
    await pump(tester, AccountPage(api: fake.api, onSignedOut: () async {}));
    expect(find.text('Pakka'), findsOneWidget);
  });

  testWidgets('a state that cannot be fetched shows no entry', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async => http.Response('{}', req.url.path.endsWith('/pakka/state') ? 502 : 200)),
    );
    await pump(tester, AccountPage(api: api, onSignedOut: () async {}));
    expect(find.text('Pakka'), findsNothing);
  });

  testWidgets('a reply renders as it streams, with a typing state while it looks something up', (tester) async {
    await pump(tester, PakkaPage(api: fake.api));
    await tester.enterText(find.byType(TextField), 'Is the server up?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Is the server up?'), findsOneWidget);
    expect(find.text('Pakka is typing'), findsOneWidget);

    fake.stream!.add(utf8.encode(_sse('start', {})));
    fake.stream!.add(utf8.encode(_sse('tool', {'name': 'status'})));
    await tester.pump();
    await tester.pump();
    expect(find.text('Looking that up'), findsOneWidget);

    fake.stream!.add(utf8.encode(_sse('delta', {'text': 'All '})));
    await tester.pump();
    await tester.pump();
    expect(find.text('All '), findsOneWidget);
    expect(find.text('Looking that up'), findsNothing);
    fake.stream!.add(utf8.encode(_sse('delta', {'text': 'good.'})));
    await tester.pump();
    await tester.pump();
    expect(find.text('All good.'), findsOneWidget);

    fake.stream!.add(utf8.encode(_sse('done', {'message_id': 'm1'})));
    await fake.stream!.close();
    await tester.pumpAndSettle();
    expect(find.text('Pakka is typing'), findsNothing);
  });

  testWidgets('a failed reply shows Try again and restores the text', (tester) async {
    await pump(tester, PakkaPage(api: fake.api));
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    fake.stream!.add(utf8.encode(_sse('error', {'code': 'model_error'})));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'hello');

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Try again'), findsNothing);
    fake.stream!.add(utf8.encode(_sse('delta', {'text': 'Hi!'})));
    fake.stream!.add(utf8.encode(_sse('done', {'message_id': 'm2'})));
    await fake.stream!.close();
    await tester.pumpAndSettle();
    expect(find.text('Hi!'), findsOneWidget);
  });

  testWidgets('a refusal before the stream is worded and keeps the text', (tester) async {
    fake.sendStatus = 409;
    await pump(tester, PakkaPage(api: fake.api));
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Pakka is busy. Try again in a moment.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('deleting a conversation removes it', (tester) async {
    fake.conversations = [
      {'id': 'a', 'title': 'Setup help'},
      {'id': 'b', 'title': 'Friend codes'},
    ];
    await pump(tester, PakkaPage(api: fake.api));
    await tester.tap(find.byTooltip('Your chats'));
    await tester.pumpAndSettle();
    expect(find.text('Setup help'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete chat').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete chat'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('DELETE /conversations/a'));
    expect(find.text('Setup help'), findsNothing);
    expect(find.text('Friend codes'), findsOneWidget);
  });

  testWidgets('the AI disclaimer and the ticket button are always visible', (tester) async {
    fake.state = {...fake.state, 'consent': false};
    await pump(tester, PakkaPage(api: fake.api));
    expect(find.textContaining('Pakka is an AI assistant and can make mistakes.'), findsOneWidget);
    expect(find.textContaining('Chats are deleted after 30 days'), findsOneWidget);
    expect(find.text('Need a person? Open a support ticket'), findsOneWidget);
  });

  group('event stream parser', () {
    Future<List<(String, String)>> parse(List<String> chunks) async => [
      await for (final e in parsePakkaEvents(Stream.fromIterable(chunks.map(utf8.encode)))) (e.kind, e.text),
    ];

    test('reads start, tool, delta, done', () async {
      expect(
        await parse([_sse('start', {}) + _sse('tool', {'name': 'x'}) + _sse('delta', {'text': 'a'}) + _sse('done', {'message_id': 'm'})]),
        [('start', ''), ('tool', 'x'), ('delta', 'a'), ('done', 'm')],
      );
    });

    test('an event split across chunks, even inside a character', () async {
      final bytes = utf8.encode(_sse('delta', {'text': 'héllo'}));
      final cut = bytes.indexOf(0xC3) + 1; // between the two bytes of é
      final out = [
        await for (final e in parsePakkaEvents(Stream.fromIterable([bytes.sublist(0, cut), bytes.sublist(cut, bytes.length - 1), bytes.sublist(bytes.length - 1)]))) (e.kind, e.text),
      ];
      expect(out, [('delta', 'héllo')]);
    });

    test('error events and CRLF line ends', () async {
      expect(await parse(['event: error\r\ndata: {"code":"busy"}\r\n\r\n']), [('error', 'busy')]);
    });
  });

  test('every Pakka string exists in every language', () {
    final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
    final keys = en.keys.where((k) => !k.toString().startsWith('@') && (k.toString().startsWith('pakka') || k.toString().startsWith('errorPakka')));
    expect(keys.length, greaterThan(30));
    for (final lang in ['de', 'es', 'fr', 'it', 'pt', 'pt_BR']) {
      final arb = jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map;
      for (final k in keys) {
        expect(arb[k], isA<String>(), reason: '$k missing from $lang');
      }
    }
  });
}

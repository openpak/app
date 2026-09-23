import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/theme.dart';
import 'package:openpak/voice.dart';
import 'package:openpak/voice_page.dart';

import 'localized.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The call without WebRTC: joining is the server's welcome, nothing more.
class _FakeSession extends VoiceSession {
  _FakeSession(super.api, super.code);
  static final started = <String>[];

  @override
  Future<void> start() async {
    started.add(code);
    roster.apply({
      'type': 'welcome',
      'self': 'me',
      'name': 'Marina',
      'room': {'code': code, 'kind': 'game', 'title': 'splatoon-2', 'max_members': 8},
      'peers': [
        {'id': 'p2', 'name': 'Pearl', 'muted': false, 'speaking': true},
      ],
      'ice_servers': [],
    });
    roster.peers['p2']!.linked = true;
    connected = true;
    notifyListeners();
  }

  @override
  void toggleMute() {
    muted = !muted;
    notifyListeners();
  }

  @override
  Future<void> leave() async {}
}

void main() {
  test('the roster: the newcomer offers to everyone there; others only answer', () {
    final r = VoiceRoster();
    final offerTo = r.apply({
      'type': 'welcome',
      'self': 'a',
      'name': 'A',
      'room': {'code': 'ABC234', 'kind': 'code'},
      'peers': [
        {'id': 'b', 'name': 'B'},
        {'id': 'c', 'name': 'C', 'muted': true},
      ],
      'ice_servers': [
        {
          'urls': ['stun:x:3478'],
        },
      ],
    });
    expect(offerTo, ['b', 'c']);
    expect(r.selfName, 'A');
    expect(r.room!.code, 'ABC234');
    expect(r.iceServers.single['urls'], ['stun:x:3478']);
    expect(r.peers['c']!.muted, isTrue);

    expect(
      r.apply({
        'type': 'join',
        'peer': {'id': 'd', 'name': 'D'},
      }),
      isEmpty,
      reason: 'a joiner offers to us, not us to it',
    );
    expect(r.peers.keys, containsAll(['b', 'c', 'd']));
    r.apply({'type': 'state', 'id': 'b', 'muted': false, 'speaking': true});
    expect(r.peers['b']!.speaking, isTrue);
    r.apply({'type': 'leave', 'id': 'c'});
    expect(r.peers.containsKey('c'), isFalse);
    r.apply({
      'type': 'join',
      'peer': {'id': 'a', 'name': 'A'},
    });
    expect(r.peers.containsKey('a'), isFalse, reason: 'you are never your own peer');
  });

  test('speaking holds between words and drops after a pause', () {
    final d = SpeakingDetector(on: 0.05, hold: const Duration(milliseconds: 500));
    final t0 = DateTime(2026);
    expect(d.feed(0.2, t0), isTrue);
    expect(d.speaking, isTrue);
    expect(d.feed(0.0, t0.add(const Duration(milliseconds: 300))), isFalse, reason: 'a gap between words');
    expect(d.feed(0.0, t0.add(const Duration(milliseconds: 600))), isTrue);
    expect(d.speaking, isFalse);
  });

  test('the socket address follows the API base', () {
    final api = OpenPakApi(baseUrl: 'https://openpak.org', token: 't');
    expect(api.voiceSocketUri('ABC234').toString(), 'wss://openpak.org/api/v1/me/voice/ws?code=ABC234');
    expect(api.voiceHeaders['Authorization'], 'Bearer t');
    expect(OpenPakApi(baseUrl: 'http://10.0.2.2:20010').voiceSocketUri('X').scheme, 'ws');
    expect(gameName('super-mario-maker-2'), 'Super Mario Maker 2');
  });

  testWidgets('the game room is found, joined, muted; a wrong code is told as such', (tester) async {
    _FakeSession.started.clear();
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient(
        (req) async => switch (req.url.path) {
          '/api/v1/me/voice' => _json({
            'room': {
              'code': 'KX7P2Q',
              'kind': 'game',
              'title': 'splatoon-2',
              'max_members': 8,
              'members': [
                {'account_id': 'me', 'display_name': 'Marina', 'in_voice': false},
                {'account_id': 'p2', 'display_name': 'Pearl', 'in_voice': true},
              ],
            },
            'max_members': 8,
          }),
          '/api/v1/me/voice/rooms/NOPE22' => _json({
            'error': 'no voice room has that code',
            'code': 'voice_room_unknown',
          }, 404),
          _ => _json({}),
        },
      ),
    );
    await tester.pumpWidget(
      localizedApp(
        theme: openPakLight(),
        home: VoicePage(api: api, sessionFactory: _FakeSession.new),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Splatoon 2 · room KX7P2Q'), findsOneWidget);
    expect(find.text('In voice chat'), findsOneWidget);
    expect(find.text('Not in voice chat'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nope22');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No voice room has that code'), findsOneWidget);
    expect(_FakeSession.started, isEmpty);
    await tester.pump(const Duration(seconds: 5)); // the toast goes
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join voice chat'));
    await tester.pumpAndSettle();
    expect(_FakeSession.started, ['KX7P2Q']);
    expect(find.text('Marina (you)'), findsOneWidget);
    expect(find.text('Speaking'), findsOneWidget);
    expect(find.text('2 of 8 connected'), findsOneWidget);

    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();
    expect(find.text('Unmute'), findsOneWidget);
    expect(find.text('Muted'), findsOneWidget);

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Join voice chat'), findsOneWidget);
  });
}

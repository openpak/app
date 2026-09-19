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

  test('an edit sends only the fields it changed', () async {
    Map<String, dynamic>? sent;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return json({'saved': true});
      }),
    );
    await api.updateProfile(country: 'IE');
    // Omitted fields must be absent, not empty strings: the server treats an
    // empty value as "leave it alone", but sending one anyway would mean a
    // country edit quietly rewrote the name.
    expect(sent, {'country': 'IE'});
  });

  test('an account with no avatar reports null rather than a broken URL',
      () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => json({
            'account_id': 'a',
            'display_name': 'Leia',
            'avatar_url': null,
            'country': 'IE',
            'birthday': '1990-01-01',
          })),
    );
    final me = await api.me();
    expect(me.avatarUrl, isNull);
    expect(me.country, 'IE');
    expect(api.absolute('/media/avatars/a/256'),
        'https://openpak.test/media/avatars/a/256');
  });

  test('a Wii/DS link rides linked_platforms beside a Switch link', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => json({
            'account_id': 'a',
            'display_name': 'Leia',
            // WD-0: a console linked by friend code is part of the person.
            'linked_platforms': [
              {'namespace': 'switch', 'link_id': 'l1'},
              {'namespace': 'wfc', 'link_id': 'l2'},
            ],
          })),
    );
    final me = await api.me();
    expect(me.linkedPlatforms, ['switch', 'wfc']);
  });

  test('declining something already gone is false, not an error', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => json({'declined': false})),
    );
    expect(await api.decline('inv-1'), isFalse);
  });

  test('requests parse, and voted is false when signed out', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      client: MockClient((_) async => json({
            'items': [
              {
                'id': 7,
                'kind': 'title',
                'name': 'Outbound',
                'console': 'Switch',
                'category': 'Third-party network (Photon)',
                'backend': 'Epic/Photon (Fusion)',
                'status': 'live',
                'notes': 'End-to-end works.',
                'votes': 12,
                'voted': false,
              }
            ]
          })),
    );
    final items = await api.requests();
    expect(items, hasLength(1));
    // A numeric id from the server is kept as a String — it is only echoed back
    // in the vote path, never used as a number.
    expect(items.single.id, '7');
    expect(items.single.name, 'Outbound');
    expect(items.single.votes, 12);
    expect(items.single.voted, isFalse);
    expect(items.single.isTitle, isTrue);
  });

  test('voting posts to the id path and returns the fresh count', () async {
    String? seenPath;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        seenPath = req.url.path;
        return json({'id': 7, 'votes': 13, 'voted': true});
      }),
    );
    final r = await api.vote('7');
    // Path param, no body; the response carries the new count.
    expect(seenPath, '/api/v1/requests/7/vote');
    expect(r.votes, 13);
    expect(r.voted, isTrue);
  });

  test('saves parse with their versions, conflicts and usage', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_t',
      client: MockClient((req) async {
        expect(req.url.path, '/api/v1/me/saves');
        return json({
          'saves': [
            {
              'platform': 'citron',
              'title_id': '0100abcd00001000',
              'versions': [
                {'id': 3, 'number': 3, 'size': 12, 'conflict': true, 'pinned': false,
                  'backend': 'local', 'parts': 1, 'created_at': '2026-09-10T12:21:23Z'},
                {'id': 1, 'number': 1, 'size': 12, 'conflict': false, 'pinned': true,
                  'backend': 's3', 'parts': 1, 'created_at': '2026-09-10T12:21:20Z',
                  'saved_at': '2026-09-10T12:00:00Z', 'device': 'smoke'},
              ],
            },
          ],
          'usage': {'allowance_used': 36, 'allowance': 268435456, 'total': 36},
        });
      }),
    );
    final data = await api.saves();
    expect(data.usage.allowanceUsed, 36);
    expect(data.saves.single.titleId, '0100abcd00001000');
    expect(data.saves.single.versions.first.conflict, true);
    expect(data.saves.single.versions.last.pinned, true);
    expect(data.saves.single.versions.last.backend, 's3');
    expect(data.saves.single.versions.last.savedAt, isNotNull);
  });

  test('storage parses, a failed bucket test reads as its detail', () async {
    var puts = 0;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_t',
      client: MockClient((req) async {
        if (req.method == 'PUT') {
          puts++;
          expect(jsonDecode(req.body)['kind'], 's3');
          expect(jsonDecode(req.body)['s3']['bucket'], 'mysaves');
          return json({'error': 'storage_test_failed', 'detail': 'write: access denied'}, status: 422);
        }
        return json({
          'connected': true, 'kind': 's3', 'endpoint': 'x.r2.cloudflarestorage.com',
          'bucket': 'mysaves', 'access_key': 'ak', 'path_style': true, 'last_test_ok': true,
          'last_error': '', 'move_state': 'done: 2 versions',
          'usage': {'allowance_used': 0, 'allowance': 268435456, 'total': 40},
        });
      }),
    );
    final st = await api.savesStorage();
    expect(st.connected, true);
    expect(st.bucket, 'mysaves');
    expect(st.lastError, isNull);
    expect(st.moveState, 'done: 2 versions');
    await expectLater(
      api.connectStorage(StorageConfig.s3(endpoint: 'x', bucket: 'mysaves', accessKey: 'ak', secretKey: 'sk')),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'write: access denied')),
    );
    expect(puts, 1);
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

  test('status reads players per network; unblock posts the account', () async {
    final seen = <String>[];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_abc',
      client: MockClient((req) async {
        seen.add('${req.method} ${req.url.path} ${req.body}');
        return json({
          'players_online': 3,
          'networks': [
            {'namespace': 'switch', 'players': 2},
            {'namespace': 'wfc', 'players': 1},
          ],
        });
      }),
    );
    final s = await api.status();
    expect(s.playersOnline, 3);
    expect(s.networks, {'switch': 2, 'wfc': 1});
    await api.unblockAccount('acct-2');
    expect(seen.last, 'POST /api/v1/me/friends/unblock {"account_id":"acct-2"}');
  });

  test('account and chat calls hit the contract paths', () async {
    final seen = <String>[];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_abc',
      client: MockClient((req) async {
        seen.add('${req.method} ${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}');
        if (req.url.path == '/api/v1/me/chat') {
          return json({'conversations': [
            {'peer': 'acct-2', 'newest': {'id': 7, 'from_account': 'acct-2', 'kind': 'invite', 'body': '', 'sent_at_unix': 60}},
          ]});
        }
        if (req.url.path == '/api/v1/me/chat/acct-2' && req.method == 'GET') {
          return json({'messages': [
            {'id': 8, 'from_account': 'acct-1', 'kind': 'text', 'body': 'hi', 'sent_at_unix': 61},
          ]});
        }
        return json({'message': {'id': 9, 'body': 'yo'}}, status: 201);
      }),
    );
    final convs = await api.conversations();
    expect(convs.single.peer, 'acct-2');
    expect(convs.single.newest.line, '[Invite message]');
    final ms = await api.chatHistory('acct-2', after: 7);
    expect(ms.single.line, 'hi');
    expect((await api.sendChat('acct-2', 'yo')).id, 9);
    await api.register(email: 'a@x.test', password: 'password-1', displayName: 'Leia');
    await api.forgotPassword('a@x.test');
    await api.changePassword('old-pass-1', 'new-pass-1');
    await api.linkWfc('1234-5678-9012');
    await api.unlink('wfc');
    expect(seen, [
      'GET /api/v1/me/chat',
      'GET /api/v1/me/chat/acct-2?after=7',
      'POST /api/v1/me/chat/acct-2',
      'POST /api/v1/register',
      'POST /api/v1/password/forgot',
      'POST /api/v1/me/password',
      'POST /api/v1/me/links/wfc',
      'DELETE /api/v1/me/links/wfc',
    ]);
  });
}

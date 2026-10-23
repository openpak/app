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
    expect(convs.single.newest.isText, isFalse); // worded by the UI: chatLine
    final ms = await api.chatHistory('acct-2', after: 7);
    expect(ms.single.isText, isTrue);
    expect((await api.sendChat('acct-2', 'yo')).id, 9);
    await api.register(email: 'a@x.test', password: 'password-1', displayName: 'Leia', handle: 'LeiaOrgana', birthday: '2000-01-02');
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

  test('a two-factor account gets a challenge, then a bearer for the code', () async {
    final sent = <String>[];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      client: MockClient((req) async {
        sent.add('${req.url.path} ${req.body}');
        if (req.url.path == '/api/v1/token') {
          return json({'two_factor_required': true, 'challenge': 'ch-1'}, status: 202);
        }
        return json({'token': 'opk_2fa', 'token_type': 'Bearer'}, status: 201);
      }),
    );
    // No token yet: the 202 must not read as signed in.
    await expectLater(
      api.signIn('a@x.test', 'password-1'),
      throwsA(isA<TwoFactorRequired>().having((e) => e.challenge, 'challenge', 'ch-1')),
    );
    expect(api.token, isNull);

    expect(await api.signInSecondFactor('ch-1', ' 123 456 '), 'opk_2fa');
    expect(api.token, 'opk_2fa');
    expect(sent.last, '/api/v1/token/2fa {"challenge":"ch-1","code":"123456"}');

    // Anything but six digits is a recovery code, as on the website.
    await api.signInSecondFactor('ch-2', 'abcde-fghij');
    expect(sent.last, '/api/v1/token/2fa {"challenge":"ch-2","recovery_code":"abcde-fghij"}');
  });

  test('a wrong second-factor code is a 401, and a lock is a 429', () async {
    var status = 401;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      client: MockClient((_) async => json({'error': 'nope'}, status: status)),
    );
    await expectLater(
      api.signInSecondFactor('ch', '000000'),
      throwsA(isA<ApiException>().having((e) => e.unauthorized, 'unauthorized', true)),
    );
    status = 429;
    await expectLater(
      api.signInSecondFactor('ch', '000000'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
    );
  });

  test('me reports email and two-factor state; absent means confirmed', () async {
    var body = <String, dynamic>{'account_id': 'a', 'email_verified': false, 'two_factor_enabled': true};
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => json(body)),
    );
    var me = await api.me();
    expect(me.emailVerified, isFalse);
    expect(me.twoFactorEnabled, isTrue);
    body = {'account_id': 'a'};
    me = await api.me();
    expect(me.emailVerified, isTrue);
    expect(me.twoFactorEnabled, isFalse);
  });

  test('a wrong code while enabling two-factor does not sign out', () async {
    var signedOut = 0;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_live',
      client: MockClient((_) async => json({'error': 'invalid code'}, status: 401)),
    )..onUnauthorized = () => signedOut++;
    await expectLater(api.twoFactorEnable('123456'), throwsA(isA<ApiException>()));
    await expectLater(api.twoFactorDisable('pw', '123456'), throwsA(isA<ApiException>()));
    expect(signedOut, 0);
    expect(api.token, 'opk_live');
  });

  test('security, friends and news calls hit the contract paths', () async {
    final seen = <String>[];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_abc',
      client: MockClient((req) async {
        seen.add('${req.method} ${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''} ${req.body}');
        return switch (req.url.path) {
          '/api/v1/me/2fa/setup' => json({'secret': 'JBSWY3DP', 'otpauth_uri': 'otpauth://totp/OpenPak:a?secret=JBSWY3DP'}),
          '/api/v1/me/2fa/enable' => json({'recovery_codes': List.generate(10, (i) => 'code-$i')}),
          '/api/v1/me/blocked' => json({'blocked': [
            {'account_id': 'b', 'display_name': 'Boba', 'blocked_at': '2026-09-01T10:00:00Z'},
          ]}),
          '/api/v1/news' => json({'articles': [
            {'slug': 's', 'title': 'Hello', 'summary': 'First.', 'body': 'First.\n\nSecond.', 'published_at': '2026-09-18T09:00:00Z'},
          ]}),
          _ => json({'message': 'ok'}),
        };
      }),
    );
    final secret = await api.twoFactorSetup('pw-1');
    expect(secret.secret, 'JBSWY3DP');
    expect(secret.otpauthUri, startsWith('otpauth://'));
    expect(await api.twoFactorEnable('123 456'), hasLength(10));
    await api.twoFactorDisable('pw-1', 'abcde-fghij');
    await api.changeEmail('new@x.test', 'pw-1');
    await api.resendVerification();
    await api.declineFriend('acct-2');
    final blocked = (await api.blocked()).single;
    expect(blocked.displayName, 'Boba');
    expect(blocked.blockedAt, DateTime.utc(2026, 9, 1, 10));
    final news = (await api.news()).single;
    expect(news.title, 'Hello');
    expect(news.publishedAt, isNotNull);
    expect(seen, [
      'POST /api/v1/me/2fa/setup {"password":"pw-1"}',
      'POST /api/v1/me/2fa/enable {"code":"123456"}',
      'POST /api/v1/me/2fa/disable {"password":"pw-1","code":"abcde-fghij"}',
      'POST /api/v1/me/email {"new_email":"new@x.test","password":"pw-1"}',
      'POST /api/v1/me/verify/resend {}',
      'POST /api/v1/me/friends/requests/decline {"account_id":"acct-2"}',
      'GET /api/v1/me/blocked ',
      'GET /api/v1/news?limit=3 ',
    ]);
  });

  test('deleting the account sends the password and code, then drops the bearer', () async {
    String? sent;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_abc',
      client: MockClient((req) async {
        sent = '${req.method} ${req.url.path} ${req.body}';
        return json({'deleted': true});
      }),
    );
    await api.deleteAccount('pw-1', code: '123456');
    expect(sent, 'DELETE /api/v1/me {"password":"pw-1","code":"123456"}');
    expect(api.token, isNull);
  });

  test('deleting a two-factor account without a code keeps everything', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 'opk_abc',
      client: MockClient((_) async => json(
            {'error': 'this account has two-factor authentication: send a code', 'two_factor_required': true},
            status: 403,
          )),
    );
    await expectLater(
      api.deleteAccount('pw-1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
    expect(api.token, 'opk_abc');
  });

  test('friend_codes uses the permanent handle and numeric codes; retired OP codes are ignored', () {
    final now = Account.fromJson({
      'friend_codes': [
        {'kind': 'handle', 'console': '', 'label': 'Handle', 'code': 'LeiaOrgana'},
        {'kind': 'wiiu', 'console': 'Wii U', 'label': 'Wii U · NNID', 'code': 'leia'},
        {'kind': '3ds', 'console': '3DS', 'label': '3DS', 'code': ''},
      ],
    });
    expect(now.friendCodes.map((c) => '${c.kind} ${c.label} ${c.code}'), ['handle Handle LeiaOrgana', 'wiiu Wii U · NNID leia']);

    final old = Account.fromJson({'openpak_code': 'OP-AB2C-D3E4', 'friend_code': 'SW-1234-5678-9012'});
    expect(old.friendCodes.map((c) => c.kind), ['switch']);
    expect(Account.fromJson({}).friendCodes, isEmpty);
  });

  test('a parental-controls list separates a live code from a paired console', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        expect(req.url.path, '/api/v1/me/parental-controls');
        return json({
          'devices': [
            {'moon_id': '00000000000000ff', 'paired': false, 'pairing_code': 'ABC234', 'expires_at': 1790000000, 'has_setting': false},
            {'moon_id': '00000000000000aa', 'paired': true, 'has_setting': true},
          ],
        });
      }),
    );

    final devices = await api.parentalDevices();
    expect(devices.map((d) => d.waiting), [true, false]);
    // A record with no live code carries none: the server drops an expired one
    // rather than let a screen show a code someone would type.
    expect(devices[1].pairingCode, '');
    expect(devices[0].expiresAt, DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000));
    expect(devices[1].expiresAt, isNull);
    expect(devices[1].hasSetting, isTrue);
  });

  test('a console reads its phase A fields, and an older server leaves them empty', () {
    final d = ParentalDevice.fromJson({
      'moon_id': '00000000000000aa',
      'paired': true,
      'has_setting': true,
      'nickname': 'Living room',
      'setting': {'functionalRestrictionLevel': 'CUSTOM'},
      'players': [
        {'id': 'p1', 'nickname': 'Leia'},
        {'nickname': 'no id, dropped'},
      ],
      'synced_at': 1790000000,
      'synced': true,
      'wrong_pin_attempts': [1790000300, 1790000100],
    });
    expect(d.nickname, 'Living room');
    expect(d.setting['functionalRestrictionLevel'], 'CUSTOM');
    expect(d.players.map((p) => '${p.id} ${p.nickname}'), ['p1 Leia']);
    expect(d.syncedAt, DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000));
    expect(d.synced, isTrue);
    expect(d.wrongPinAttempts.first, DateTime.fromMillisecondsSinceEpoch(1790000300 * 1000));

    final old = ParentalDevice.fromJson({'moon_id': '00000000000000aa', 'paired': true, 'has_setting': true, 'setting': 'junk'});
    expect(old.nickname, '');
    expect(old.setting, isEmpty);
    expect(old.players, isEmpty);
    expect(old.syncedAt, isNull);
    // Unsaid, not false: the list keeps its older pill rather than claim
    // the console is behind.
    expect(old.synced, isNull);
    expect(old.wrongPinAttempts, isEmpty);
  });

  test('a console with no PIN on record answers null, not an error', () async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        expect(req.url.path, '/api/v1/me/parental-controls/00000000000000aa/pin');
        return json({'error': 'not found'}, status: 404);
      }),
    );
    expect(await api.parentalPin('00000000000000aa'), isNull);
  });

  test('pairing posts and returns a code that is not yet paired', () async {
    var posts = 0;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        posts++;
        expect(req.method, 'POST');
        expect(req.url.path, '/api/v1/me/parental-controls/pairing');
        return json({'moon_id': '00000000000000ff', 'pairing_code': 'ABC234', 'expires_at': 1790000000}, status: 201);
      }),
    );

    final d = await api.parentalPair();
    expect(posts, 1);
    expect(d.pairingCode, 'ABC234');
    expect(d.paired, isFalse);
    expect(d.waiting, isTrue);
  });
}

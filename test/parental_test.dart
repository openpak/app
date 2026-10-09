import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_auth/local_auth.dart';
import 'package:openpak/api.dart';
import 'package:openpak/parental_console_page.dart';
import 'package:openpak/parental_controls_page.dart';
import 'package:openpak/parental_editor_page.dart';
import 'package:openpak/parental_lock.dart';
import 'package:openpak/theme.dart';
import 'package:openpak/widgets.dart';

import 'localized.dart';

/// The phone's unlock, answered by the test.
class _FakeAuth implements LocalAuthentication {
  _FakeAuth({this.supported = true, this.result = true, this.error});
  final bool supported;
  final bool result;
  final LocalAuthException? error;
  int asked = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object?> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    asked++;
    if (error != null) throw error!;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _console = {
  'moon_id': '00000000000000aa',
  'paired': true,
  'has_setting': true,
  'nickname': 'Living room',
  'synced': true,
  'synced_at': 1790000000,
  'players': [],
  'setting': {'functionalRestrictionLevel': 'NONE'},
};

void main() {
  group('the lock decides', () {
    Future<LockOutcome> outcome(_FakeAuth auth, {TargetPlatform platform = TargetPlatform.android}) =>
        ParentalLock(auth: auth, platform: platform).unlock('why');

    test('allowed, denied, no lock screen, password', () async {
      expect(await outcome(_FakeAuth()), LockOutcome.allowed);
      expect(await outcome(_FakeAuth(result: false)), LockOutcome.denied);
      expect(await outcome(_FakeAuth(supported: false)), LockOutcome.noLockScreen);
      expect(
        await outcome(_FakeAuth(error: const LocalAuthException(code: LocalAuthExceptionCode.noCredentialsSet))),
        LockOutcome.noLockScreen,
      );
      expect(
        await outcome(_FakeAuth(error: const LocalAuthException(code: LocalAuthExceptionCode.userCanceled))),
        LockOutcome.denied,
      );
      // iOS without a passcode is a phone with no lock screen, not the
      // password path: removing the lock must not be a way around it.
      expect(await outcome(_FakeAuth(supported: false), platform: TargetPlatform.iOS), LockOutcome.noLockScreen);
      final desktop = _FakeAuth();
      expect(await outcome(desktop, platform: TargetPlatform.linux), LockOutcome.password);
      expect(desktop.asked, 0);
    });

    test('asks again only after more than 60 seconds away', () {
      final away = DateTime(2026, 9, 27, 12);
      var now = away.add(const Duration(seconds: 60));
      final lock = ParentalLock(auth: _FakeAuth(), now: () => now);
      expect(lock.expired(null), isFalse);
      expect(lock.expired(away), isFalse);
      now = away.add(const Duration(seconds: 61));
      expect(lock.expired(away), isTrue);
    });
  });

  Future<void> background(WidgetTester tester) async {
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the PIN is fetched only when shown, and gone once the app is backgrounded', (tester) async {
    var fetched = 0;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/pin')) {
          fetched++;
          return _json({'unlock_code': '8759'});
        }
        return _json({'devices': [_console]});
      }),
    );
    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: ParentalConsolePage(api: api, device: ParentalDevice.fromJson(_console)),
    ));
    await tester.pumpAndSettle();
    expect(fetched, 0);
    expect(find.text('••••'), findsOneWidget);

    await tester.tap(find.text('Show PIN'));
    await tester.pumpAndSettle();
    expect(find.text('8759'), findsOneWidget);

    await background(tester);
    expect(find.text('8759'), findsNothing);
    expect(find.text('••••'), findsOneWidget);

    // Nothing was kept: showing it again asks the server again.
    await foreground(tester);
    await tester.tap(find.text('Show PIN'));
    await tester.pumpAndSettle();
    expect(fetched, 2);
  });

  testWidgets('back after more than a minute, the parental screens close and ask again', (tester) async {
    final auth = _FakeAuth();
    var now = DateTime(2026, 9, 27, 12);
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => _json({'devices': [_console]})),
    );
    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: ParentalControlsPage(api: api, lock: ParentalLock(auth: auth, now: () => now)),
    ));
    await tester.pumpAndSettle();
    expect(auth.asked, 1);

    await tester.tap(find.text('Living room'));
    await tester.pumpAndSettle();
    expect(find.text('Show PIN'), findsOneWidget);

    // Thirty seconds away: nothing asked, the console still open.
    await background(tester);
    now = now.add(const Duration(seconds: 30));
    await foreground(tester);
    expect(auth.asked, 1);
    expect(find.text('Show PIN'), findsOneWidget);

    await background(tester);
    now = now.add(const Duration(seconds: 61));
    await foreground(tester);
    expect(auth.asked, 2);
    expect(find.text('Show PIN'), findsNothing);
  });

  testWidgets('a phone with no screen lock says so and shows nothing', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((_) async => _json({'devices': [_console]})),
    );
    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: ParentalControlsPage(api: api, lock: ParentalLock(auth: _FakeAuth(supported: false))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('no screen lock'), findsOneWidget);
    expect(find.text('Living room'), findsNothing);
  });

  group('the editor', () {
    test('a save sends the whole served document, changed only where the form changed it', () {
      final served = {
        'functionalRestrictionLevel': 'CUSTOM',
        'customSettings': {
          'ageRestriction': {'restriction': 'RESTRICTED', 'ratingAge': 12},
          'ugcRestriction': {
            'restriction': 'UNRESTRICTED',
            'applications': {
              for (var i = 0; i < 47; i++) '0100000000${i.toString().padLeft(2, '0')}0000': {'restriction': 'RESTRICTED'},
            },
          },
        },
        'whitelistedApplications': {'0100b3c014bda000': {'safeLaunch': 'ALLOW'}},
        'aKeyFromANewerConsole': {'nested': [1, 2]},
      };
      final before = jsonEncode(served);
      final doc = mergeSetting(served, {
        'customSettings.ageRestriction.ratingAge': 7,
        'playTimerRegulations.dailyRegulations.timeToPlayInOneDay.enabled': true,
        'playTimerRegulations.dailyRegulations.timeToPlayInOneDay.limitTime': 90,
      });

      expect(jsonEncode(served), before, reason: 'the served document is not written to');
      final custom = doc['customSettings'] as Map;
      expect(custom['ageRestriction'], {'restriction': 'RESTRICTED', 'ratingAge': 7});
      expect((custom['ugcRestriction'] as Map)['applications'], hasLength(47));
      expect(doc['whitelistedApplications'], served['whitelistedApplications']);
      expect(doc['aKeyFromANewerConsole'], {'nested': [1, 2]});
      // A timer touched for the first time is a whole one.
      expect(doc['playTimerRegulations'], {
        'dailyRegulations': {
          'timeToPlayInOneDay': {'enabled': true, 'limitTime': 90},
          'bedtime': {'enabled': false},
        },
        'timerMode': 'DAILY',
        'restrictionMode': 'ALARM',
      });
    });

    test('numbers stay inside the console\'s own bounds; a PIN is four digits', () {
      expect(parentalNumber('255', parentalMax['ratingAge']!), 255);
      expect(parentalNumber('256', parentalMax['ratingAge']!), isNull);
      expect(parentalNumber('360', parentalMax['limitTime']!), 360);
      expect(parentalNumber('361', parentalMax['limitTime']!), isNull);
      expect(parentalNumber('0', parentalMax['limitTime']!), 0);
      expect(parentalNumber('', parentalMax['limitTime']!), isNull);
      expect(parentalNumber('-1', parentalMax['hour']!), isNull);
      expect(parentalNumber('23', parentalMax['hour']!), 23);
      expect(parentalNumber('60', parentalMax['minute']!), isNull);
      expect(parentalNumber('1.5', parentalMax['limitTime']!), isNull);
      for (final ok in ['0000', '4827']) {
        expect(validNewPin(ok), isTrue);
      }
      for (final bad in ['', '123', '12345', '12a4', ' 1234', '87590000']) {
        expect(validNewPin(bad), isFalse, reason: bad);
      }
    });

    testWidgets('a value past the bound is caught in the form; a refusal lands on its field', (tester) async {
      final sent = <Map<String, dynamic>>[];
      final api = OpenPakApi(
        baseUrl: 'https://openpak.test',
        token: 't',
        client: MockClient((req) async {
          expect(req.method, 'PUT');
          expect(req.url.path, '/api/v1/me/parental-controls/00000000000000aa/setting');
          sent.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _json({
            'error': 'not in the console\'s parse table',
            'code': 'invalid_setting',
            'path': 'customSettings.ageRestriction.ratingAge',
          }, status: 400);
        }),
      );
      final device = ParentalDevice.fromJson({
        ..._console,
        'setting': {
          'functionalRestrictionLevel': 'CUSTOM',
          'customSettings': {
            'ageRestriction': {'restriction': 'RESTRICTED', 'ratingAge': 12},
          },
        },
      });
      await tester.pumpWidget(localizedApp(theme: openPakLight(), home: ParentalEditorPage(api: api, device: device)));
      await tester.pumpAndSettle();

      const age = ValueKey('parental:customSettings.ageRestriction.ratingAge');
      await tester.enterText(find.descendant(of: find.byKey(age), matching: find.byType(TextFormField)), '300');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number from 0 to 255.'), findsOneWidget);
      expect(sent, isEmpty);

      await tester.enterText(find.descendant(of: find.byKey(age), matching: find.byType(TextFormField)), '13');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(sent.single['setting']['customSettings']['ageRestriction']['ratingAge'], 13);
      expect(
        find.descendant(of: find.byKey(age), matching: find.text('The console cannot take this value.')),
        findsOneWidget,
      );
      expect(find.text('The console cannot take this value.'), findsOneWidget);
      expect(parentalFieldFor('playTimerRegulations.dailyRegulations.bedtime.startingTime.hour', [
        'playTimerRegulations.dailyRegulations.bedtime.enabled',
        'playTimerRegulations.dailyRegulations.bedtime.startingTime',
      ]), 'playTimerRegulations.dailyRegulations.bedtime.startingTime');
      expect(parentalFieldFor('whitelistedApplications.0100b3c014bda000', ['functionalRestrictionLevel']), isNull);
    });
  });

  testWidgets('a new PIN needs the phone\'s unlock, four digits twice, and says the old one still works', (tester) async {
    final puts = <Object?>[];
    final auth = _FakeAuth(result: false);
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        if (req.method == 'PUT') {
          puts.add(jsonDecode(req.body));
          return http.Response('', 204);
        }
        return _json({
          'devices': [
            {..._console, 'synced': puts.isEmpty},
          ],
        });
      }),
    );
    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: ParentalConsolePage(
        api: api,
        device: ParentalDevice.fromJson(_console),
        lock: ParentalLock(auth: auth),
      ),
    ));
    await tester.pumpAndSettle();

    // Refused at the phone's unlock: no dialog, nothing sent.
    await tester.ensureVisible(find.text('Change PIN'));
    await tester.tap(find.text('Change PIN'));
    await tester.pumpAndSettle();
    expect(auth.asked, 1);
    expect(find.text('New PIN'), findsNothing);
    expect(puts, isEmpty);

    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: ParentalConsolePage(
        api: api,
        device: ParentalDevice.fromJson(_console),
        lock: ParentalLock(auth: _FakeAuth()),
        key: const ValueKey('allowed'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Change PIN'));
    await tester.tap(find.text('Change PIN'));
    await tester.pumpAndSettle();

    Future<void> type(String first, String second) async {
      await tester.enterText(find.widgetWithText(TextFormField, 'New PIN'), first);
      await tester.enterText(find.widgetWithText(TextFormField, 'New PIN again'), second);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    await type('123', '123');
    expect(find.text('The PIN must be four digits.'), findsOneWidget);
    // The field takes digits only, and four of them.
    await tester.enterText(find.widgetWithText(TextFormField, 'New PIN'), '12a456');
    expect(tester.widget<EditableText>(find.byType(EditableText).first).controller.text, '1245');
    await type('4827', '4821');
    expect(find.text('The two PINs do not match.'), findsOneWidget);
    expect(puts, isEmpty);

    await type('4827', '4827');
    expect(puts, [
      {'unlock_code': '4827'},
    ]);
    expect(find.text('4827'), findsOneWidget);
    expect(find.textContaining('the old one is still the one that works'), findsOneWidget);
  });

  test('play activity reads days and titles, with and without a name; an older server has none', () async {
    var status = 200;
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async {
        expect(req.url.path, '/api/v1/me/parental-controls/00000000000000aa/activity');
        expect(req.url.queryParameters['days'], '7');
        return status == 404
            ? _json({'error': 'not found'}, status: 404)
            : _json({
                'days': [
                  {
                    'date': '2026-09-27',
                    'total_minutes': 95,
                    'titles': [
                      {'title_id': '0100b3c014bda000', 'name': 'Stardew Valley', 'minutes': 60},
                      {'title_id': '01001b300b9be000', 'minutes': 20},
                    ],
                  },
                  {'date': '2026-09-26', 'total_minutes': 15, 'titles': []},
                ],
              });
      }),
    );
    final days = await api.parentalActivity('00000000000000aa');
    expect(days.map((d) => (d.date, d.totalMinutes)), [('2026-09-27', 95), ('2026-09-26', 15)]);
    expect(days.first.titles.map((t) => (t.titleId, t.name, t.minutes)), [
      ('0100b3c014bda000', 'Stardew Valley', 60),
      ('01001b300b9be000', '', 20),
    ]);
    // An older server: no players and no anonymous time.
    expect(days.first.titles.first.players, isEmpty);
    expect(days.first.titles.first.anonymousMinutes, 0);
    expect(days.last.titles, isEmpty);
    status = 404;
    expect(await api.parentalActivity('00000000000000aa'), isEmpty);
  });

  testWidgets('play activity shows time used per day and titles by name or id, and one line when none', (tester) async {
    var days = <Object>[
      {
        'date': '2026-09-27',
        'total_minutes': 95,
        'titles': [
          {'title_id': '0100b3c014bda000', 'name': 'Stardew Valley', 'minutes': 60},
          {'title_id': '01001b300b9be000', 'minutes': 20},
        ],
      },
      {'date': '2026-09-26', 'total_minutes': 15, 'titles': []},
      {'date': '2026-09-25', 'total_minutes': 0, 'titles': []},
    ];
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async => req.url.path.endsWith('/activity')
          ? _json({'days': days})
          : _json({'devices': [_console]})),
    );
    Future<void> open() async {
      await tester.pumpWidget(localizedApp(
        theme: openPakLight(),
        home: ParentalConsolePage(api: api, device: ParentalDevice.fromJson(_console), key: UniqueKey()),
      ));
      await tester.pumpAndSettle();
    }

    await open();
    await tester.scrollUntilVisible(find.text('Stardew Valley'), 200);
    expect(find.text('Play activity'), findsOneWidget);
    expect(find.text('Time used'), findsNWidgets(2), reason: 'the day with 0 minutes is left out');
    expect(find.text('95 minutes'), findsOneWidget);
    expect(find.text('01001b300b9be000'), findsOneWidget);
    expect(find.text('15 minutes'), findsOneWidget);

    days = [];
    await open();
    await tester.scrollUntilVisible(find.text('No play time recorded yet.'), 200);
    expect(find.text('Play activity'), findsOneWidget);
    expect(find.text('Time used'), findsNothing);
  });

  group('under a status bar, no parental screen starts under its app bar', () {
    // The first panel's top at scroll offset 0, against the bottom of the
    // app bar on screen: what a phone showed wrong in v0.16.0.
    void clear(WidgetTester tester, String screen) {
      final bar = tester.getRect(find.byType(AppBar)).bottom;
      final panel = tester.getRect(find.byType(Panel).first).top;
      expect(panel, greaterThanOrEqualTo(bar), reason: '$screen: panel at $panel, bar ends at $bar');
    }

    Future<void> open(WidgetTester tester, ParentalLock lock, http.Client client) async {
      tester.view.padding = const FakeViewPadding(top: 72); // 24 logical at the test's 3x
      addTearDown(tester.view.resetPadding);
      final api = OpenPakApi(baseUrl: 'https://openpak.test', token: 't', client: client);
      await tester.pumpWidget(localizedApp(theme: openPakLight(), home: ParentalControlsPage(api: api, lock: lock)));
      await tester.pumpAndSettle();
    }

    testWidgets('the gate while locked', (tester) async {
      await open(tester, ParentalLock(auth: _FakeAuth(result: false)), MockClient((_) async => _json({'devices': []})));
      clear(tester, 'gate');
    });

    testWidgets('the list, a console, and its editor, opened as the app opens them', (tester) async {
      await open(
        tester,
        ParentalLock(auth: _FakeAuth()),
        MockClient((req) async => req.url.path.endsWith('/activity')
            ? _json({'days': []})
            : _json({'devices': [_console]})),
      );
      clear(tester, 'list');

      await tester.tap(find.text('Living room'));
      await tester.pumpAndSettle();
      clear(tester, 'console');

      await tester.tap(find.text('Change restrictions'));
      await tester.pumpAndSettle();
      clear(tester, 'editor');
    });
  });

  group('naming a console', () {
    test('the list reads the name, whether the parent chose it, the serial and the firmware', () {
      final named = ParentalDevice.fromJson({
        ..._console,
        'nickname': 'Kids room',
        'named': true,
        'serial_number': 'XKJ70000000001',
        'firmware': '22.5.0',
      });
      expect((named.nickname, named.named, named.serialNumber, named.firmware),
          ('Kids room', true, 'XKJ70000000001', '22.5.0'));

      // An older server: none of the new fields, and nothing breaks.
      final old = ParentalDevice.fromJson({'moon_id': '00000000000000aa', 'paired': true});
      expect((old.nickname, old.named, old.serialNumber, old.firmware), ('', false, '', ''));

      // Wrong types and empty strings read as absent.
      final odd = ParentalDevice.fromJson({
        ..._console,
        'nickname': 'Switch ···0001',
        'named': 'yes',
        'serial_number': 42,
        'firmware': '',
      });
      expect((odd.nickname, odd.named, odd.serialNumber, odd.firmware), ('Switch ···0001', false, '', ''));
    });

    testWidgets('rename sends the trimmed name and shows a refusal on the field', (tester) async {
      final sent = <Object?>[];
      var refuse = true;
      final api = OpenPakApi(
        baseUrl: 'https://openpak.test',
        token: 't',
        client: MockClient((req) async {
          if (req.method == 'PUT') {
            expect(req.url.path, '/api/v1/me/parental-controls/00000000000000aa/name');
            sent.add(jsonDecode(req.body));
            return refuse
                ? _json({'error': 'name too long', 'code': 'invalid_name'}, status: 400)
                : http.Response('', 204);
          }
          return _json({'devices': [_console]});
        }),
      );
      final device = ParentalDevice.fromJson({..._console, 'nickname': 'Switch ···0001', 'named': false});
      await tester.pumpWidget(localizedApp(theme: openPakLight(), home: ParentalConsolePage(api: api, device: device)));
      await tester.pumpAndSettle();
      expect(find.text('Switch ···0001'), findsWidgets);

      await tester.tap(find.byTooltip('Rename'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Console name');
      // A default name is not prefilled, and nothing typed is nothing to save.
      expect(tester.widget<TextField>(field).controller!.text, '');
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(field, '  Kids room  ');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(sent, [
        {'name': 'Kids room'},
      ]);
      expect(
        find.descendant(of: field, matching: find.text('A name can be up to 32 characters, without control characters.')),
        findsOneWidget,
      );

      refuse = false;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Name saved.'), findsOneWidget);
    });
  });

  test('who played a title: named players, a user gone from the console, and time with no user', () {
    final day = PlayDay.fromJson({
      'date': '2026-09-27',
      'total_minutes': 30,
      'titles': [
        {
          'title_id': '0100b3c014bda000',
          'name': 'Moving Out 2',
          'minutes': 25,
          'players': [
            {'id': '10000000_00b20002_00000000_00000001', 'nickname': 'Leia', 'minutes': 13},
            {'id': '2', 'minutes': 7},
            {'nickname': 'no id', 'minutes': 1},
          ],
          'anonymous_minutes': 5,
        },
      ],
    });
    final title = day.titles.single;
    expect(title.players, [
      (id: '10000000_00b20002_00000000_00000001', nickname: 'Leia', minutes: 13),
      (id: '2', nickname: '', minutes: 7),
    ]);
    expect(title.anonymousMinutes, 5);
  });

  testWidgets('play activity names who played, with a line for a gone user and one for no user', (tester) async {
    final api = OpenPakApi(
      baseUrl: 'https://openpak.test',
      token: 't',
      client: MockClient((req) async => switch (req.url.path) {
            final p when p.endsWith('/activity') => _json({
                'days': [
                  {
                    'date': '2026-09-27',
                    'total_minutes': 30,
                    'titles': [
                      {
                        'title_id': '0100b3c014bda000',
                        'name': 'Moving Out 2',
                        'minutes': 25,
                        'players': [
                          {'id': 'a', 'nickname': 'Leia', 'minutes': 13},
                          {'id': 'b', 'minutes': 7},
                        ],
                        'anonymous_minutes': 5,
                      },
                      {'title_id': '01001b300b9be000', 'minutes': 3, 'players': [], 'anonymous_minutes': 0},
                    ],
                  },
                ],
              }),
            final p when p.endsWith('/image') => http.Response('', 404),
            _ => _json({'devices': [_console]}),
          }),
    );
    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: ParentalConsolePage(api: api, device: ParentalDevice.fromJson(_console)),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Moving Out 2'), 200);
    expect(find.text('Leia'), findsOneWidget);
    expect(find.text('13 minutes'), findsOneWidget);
    expect(find.text('A user no longer on this console'), findsOneWidget);
    expect(find.text('No user selected'), findsOneWidget);
    expect(find.text('5 minutes'), findsOneWidget);
  });
}

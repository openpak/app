import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_auth/local_auth.dart';
import 'package:openpak/api.dart';
import 'package:openpak/parental_console_page.dart';
import 'package:openpak/parental_controls_page.dart';
import 'package:openpak/parental_lock.dart';
import 'package:openpak/theme.dart';

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
}

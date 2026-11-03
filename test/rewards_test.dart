import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/l10n.dart';
import 'package:openpak/rewards_page.dart';
import 'package:openpak/rewards_theme.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

Map<String, Object?> tile(String key, String state, {Map<String, Object?> more = const {}}) => {
  'key': key,
  'name': 'Name $key',
  'label': 'Label $key',
  'img': '/static/rewards/$key.png',
  'state': state,
  'percent': 40,
  'progress': '12 / 30',
  'earned': 0,
  'single': true,
  'equipped': false,
  'complete': false,
  ...more,
};

Map<String, Object?> item(String id, String kind, {int? price = 100, Map<String, Object?> more = const {}}) => {
  'id': id,
  'kind': kind,
  'kind_label': kind == 'theme' ? 'Theme' : 'Badge',
  'name': 'Item $id',
  'description': 'About $id',
  'img': '/account/rewards/preview/$id',
  'wide': kind == 'theme',
  'price': price,
  'need': 0,
  'after': 20,
  'affordable': true,
  'owned': false,
  'equipped': false,
  'limited': false,
  'where': '',
  'soon': false,
  ...more,
};

/// The shape of GET /me/rewards (website internal/pages/rewards_api.go).
Map<String, Object?> fullView() => {
  'balance': 120,
  'frozen': false,
  'paused': false,
  'showcase_public': true,
  'today_points': 3,
  'today_cap': 8,
  'today_percent': 37,
  'cap_reached': false,
  'more': 5,
  'play_time': '4 h',
  'owned': 2,
  'ready': 1,
  'affordable': 2,
  'next_kind': 'claim',
  'next_text': 'Rewards ready to claim: 1',
  'badge': {'kind': 'badge', 'id': 'badge-founder', 'name': 'Founder', 'img': '/account/rewards/preview/badge-founder'},
  'slots': [
    {'kind': 'badge', 'label': 'Badge', 'id': 'badge-founder', 'name': 'Founder', 'img': '/account/rewards/preview/badge-founder'},
    {'kind': 'profile_icon', 'label': 'Profile icon', 'id': '', 'name': ''},
    {'kind': 'theme', 'label': 'Theme', 'id': '', 'name': ''},
  ],
  'ready_tiles': [
    tile('daily-play-30', 'ready', more: {'claim_text': 'Claim 10 points', 'mission_id': 'daily-play-30', 'period': '2026-11-02', 'percent': 100}),
  ],
  'tiles': [
    tile('kart', 'progress', more: {
      'single': false,
      'pips': [true, true, false, false],
      'earned': 2,
      'reward': '+50 points',
      'tiers': [
        {'finish': 'Wood', 'img': '/account/rewards/preview/kart-wood', 'target': '5 sessions', 'points': '10 points', 'state': 'earned', 'ready': false},
        {'finish': 'Bronze', 'img': '/account/rewards/preview/kart-bronze', 'target': '20 sessions', 'state': 'current', 'ready': false},
        {'finish': 'Gold', 'target': '50 sessions', 'state': 'locked', 'ready': false},
      ],
    }),
  ],
  'done': [tile('first-online', 'done', more: {'complete': true, 'progress': 'Done'})],
  'ledger': [
    {'img': '/static/rewards/play.png', 'title': 'Play time', 'sub': '2 Nov', 'delta': 2, 'points': '+2'},
  ],
  'shop': [
    {
      'kind': 'badge',
      'label': 'Badges',
      'wide': false,
      'items': [item('badge-star', 'badge'), item('badge-pricey', 'badge', price: 500, more: {'need': 380, 'affordable': false})],
    },
    {
      'kind': 'theme',
      'label': 'Themes',
      'wide': true,
      'items': [item('theme-dusk', 'theme', price: 200, more: {'need': 80, 'affordable': false})],
    },
  ],
  'upcoming': [item('badge-winter', 'badge', more: {'soon': true, 'when': 'Coming 1 Dec'})],
  'mine': [
    {
      'kind': 'badge',
      'label': 'Badges',
      'wide': false,
      'tiles': [
        tile('friends', 'earned', more: {'single': false, 'pips': [true, false], 'earned': 1, 'equip_item': 'badge-friends-1', 'label': 'Friends tier 1'}),
      ],
      'items': [item('badge-founder', 'badge', more: {'owned': true, 'equipped': true})],
    },
    {
      'kind': 'theme',
      'label': 'Themes',
      'wide': true,
      'items': [item('theme-night', 'theme', more: {'owned': true})],
    },
  ],
};

http.Response json(Object? body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

class Fake {
  Map<String, Object?> view = fullView();
  final writes = <String>[];
  final headers = <Map<String, String>>[];
  int redeemFailures = 0;
  int status = 200;

  OpenPakApi get api => OpenPakApi(
    baseUrl: 'https://openpak.test',
    token: 't',
    client: MockClient((req) async {
      final path = req.url.path;
      if (req.method == 'GET' && path == '/api/v1/me/rewards') {
        return status == 200 ? json(view) : json({'error': 'off', 'code': 'rewards_unavailable'}, status);
      }
      if (req.method == 'GET' && path == '/api/v1/me/rewards/theme') return json({'theme': null});
      if (req.method == 'GET' && path.startsWith('/themes/')) {
        return json({'id': 'theme-dusk', 'name': 'Dusk', 'light': _dusk, 'dark': _dusk});
      }
      writes.add('${req.method} $path ${req.body}');
      headers.add(req.headers);
      if (path.endsWith('/redeem') && redeemFailures > 0) {
        redeemFailures--;
        return json({'error': 'x', 'code': 'rewards_unavailable'}, 502);
      }
      if (path.endsWith('/claim')) return json({'points': 10});
      return json({'ok': true});
    }),
  );
}

const _dusk = {
  'paper': '#102030',
  'ink': '#f0f0f0',
  'accent': '#ff8800',
  'on-accent': '#000000',
};

void main() {
  late Fake fake;
  setUp(() => fake = Fake());

  Future<void> pump(WidgetTester tester, {RewardsThemeController? controller}) async {
    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app = localizedApp(theme: openPakLight(), home: RewardsPage(api: fake.api));
    if (controller != null) app = RewardsThemeScope(controller: controller, child: app);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  group('parsing', () {
    test('a full RewardsView', () {
      final v = RewardsView.fromJson(fullView());
      expect(v.balance, 120);
      expect(v.todayCap, 8);
      expect(v.badge?.id, 'badge-founder');
      expect(v.slot('badge')?.name, 'Founder');
      expect(v.slot('theme'), isNull);
      expect(v.readyTiles.single.claimText, 'Claim 10 points');
      expect(v.tiles.single.pips, [true, true, false, false]);
      expect(v.tiles.single.tiers.map((t) => t.state), ['earned', 'current', 'locked']);
      expect(v.tiles.single.isLadder, isTrue);
      expect(v.shop.first.items.last.need, 380);
      expect(v.shop.first.items.last.price, 500);
      expect(v.upcoming.single.when, 'Coming 1 Dec');
      expect(v.mine.first.tiles.single.equipItem, 'badge-friends-1');
      expect(v.ledger.single.delta, 2);
    });

    test('a bare object does not throw', () {
      final v = RewardsView.fromJson({});
      expect(v.balance, 0);
      expect(v.shop, isEmpty);
      expect(v.badge, isNull);
    });

    test('an item without a price', () {
      expect(RewardsItem.fromJson({'id': 'x', 'price': null}).price, isNull);
    });
  });

  group('missions', () {
    testWidgets('header, ready first, then in progress, then completed', (tester) async {
      await pump(tester);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('Pak Points'), findsOneWidget);
      expect(find.text('3 of 8'), findsOneWidget);
      expect(find.text('Rewards ready to claim: 1'), findsOneWidget);
      final ready = tester.getTopLeft(find.text('Label daily-play-30')).dy;
      final progress = tester.getTopLeft(find.text('Label kart')).dy;
      final done = tester.getTopLeft(find.text('Label first-online')).dy;
      expect(ready < progress && progress < done, isTrue);
      expect(find.text('Recent points'), findsOneWidget);
      expect(find.text('Play time'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('a ladder card shows pips and opens its tiers', (tester) async {
      await pump(tester);
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '2 of 4 tiers earned'), findsOneWidget);
      expect(find.text('+50 points'), findsOneWidget);
      await tester.tap(find.text('Label kart'));
      await tester.pumpAndSettle();
      expect(find.text('All tiers'), findsOneWidget);
      expect(find.text('Wood'), findsOneWidget);
      expect(find.text('Earned'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
    });

    testWidgets('claim sends the mission and period, then refreshes', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Claim 10 points'));
      await tester.pumpAndSettle();
      expect(fake.writes, ['POST /api/v1/me/rewards/claim {"mission":"daily-play-30","period":"2026-11-02"}']);
      expect(find.text('Claimed 10 points.'), findsOneWidget);
    });

    testWidgets('a frozen account cannot claim', (tester) async {
      fake.view = {...fullView(), 'frozen': true};
      await pump(tester);
      expect(find.textContaining('Rewards are frozen'), findsOneWidget);
      final b = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Claim 10 points'));
      expect(b.onPressed, isNull);
    });

    testWidgets('rewards off on this deployment is calm, not an error', (tester) async {
      fake.status = 503;
      await pump(tester);
      expect(find.text('Rewards are not available right now.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('shop', () {
    Future<void> openShop(WidgetTester tester) async {
      await tester.tap(find.text('Shop').first);
      await tester.pumpAndSettle();
    }

    testWidgets('groups, filter chips, coming soon', (tester) async {
      await pump(tester);
      await openShop(tester);
      expect(find.text('Item badge-star'), findsOneWidget);
      expect(find.text('Item theme-dusk'), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('Coming 1 Dec'), findsOneWidget);
      await tester.tap(find.text('Themes').first);
      await tester.pumpAndSettle();
      expect(find.text('Item badge-star'), findsNothing);
      expect(find.text('Item theme-dusk'), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);
    });

    testWidgets('buying confirms, sends an idempotency key and reports', (tester) async {
      await pump(tester);
      await openShop(tester);
      await tester.tap(find.text('Item badge-star'));
      await tester.pumpAndSettle();
      expect(find.text('Balance afterwards'), findsOneWidget);
      expect(find.text('Spend 100 points on Item badge-star?'), findsOneWidget);
      await tester.tap(find.text('Redeem for 100 points'));
      await tester.pumpAndSettle();
      expect(fake.writes.single, 'POST /api/v1/me/rewards/redeem {"item":"badge-star"}');
      expect(fake.headers.single['Idempotency-Key'], matches(RegExp(r'^[0-9a-f]{24}$')));
      expect(find.text('Item badge-star is yours. You can find it in My items.'), findsOneWidget);
    });

    testWidgets('a failed purchase can be retried with the same key', (tester) async {
      fake.redeemFailures = 1;
      await pump(tester);
      await openShop(tester);
      await tester.tap(find.text('Item badge-star'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redeem for 100 points'));
      await tester.pumpAndSettle();
      expect(find.text('Rewards are not available right now.'), findsOneWidget);
      await tester.tap(find.text('Redeem for 100 points'));
      await tester.pumpAndSettle();
      expect(fake.writes.length, 2);
      expect(fake.headers[0]['Idempotency-Key'], fake.headers[1]['Idempotency-Key']);
    });

    testWidgets('too expensive: need N more and a disabled button', (tester) async {
      await pump(tester);
      await openShop(tester);
      await tester.tap(find.text('Item badge-pricey'));
      await tester.pumpAndSettle();
      expect(find.text('You need 380 more points.'), findsOneWidget);
      final b = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Redeem for 500 points'));
      expect(b.onPressed, isNull);
      expect(fake.writes, isEmpty);
    });
  });

  group('my items', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('My items').first);
      await tester.pumpAndSettle();
    }

    testWidgets('slots, unequip, equip', (tester) async {
      await pump(tester);
      await open(tester);
      expect(find.text('Equipped now'), findsOneWidget);
      expect(find.text('Nothing equipped'), findsNWidgets(2));
      await tester.tap(find.text('Unequip'));
      await tester.pumpAndSettle();
      expect(fake.writes.last, 'POST /api/v1/me/rewards/equip {"slot":"badge","item":""}');
      expect(find.text('Unequipped.'), findsOneWidget);
      await tester.tap(find.text('Equip').first);
      await tester.pumpAndSettle();
      expect(fake.writes.last, 'POST /api/v1/me/rewards/equip {"slot":"badge","item":"badge-friends-1"}');
      expect(find.text('Friends tier 1 is equipped.'), findsOneWidget);
    });

    testWidgets('an owned theme equips into the theme slot', (tester) async {
      await pump(tester);
      await open(tester);
      await tester.ensureVisible(find.text('Item theme-night'));
      await tester.tap(find.widgetWithText(FilledButton, 'Equip').last);
      await tester.pumpAndSettle();
      expect(fake.writes.last, 'POST /api/v1/me/rewards/equip {"slot":"theme","item":"theme-night"}');
    });
  });

  group('settings', () {
    testWidgets('switches are saved together', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause earning points'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(fake.writes.single, 'POST /api/v1/me/rewards/settings {"showcase":true,"paused":true}');
      expect(find.text('Settings saved.'), findsOneWidget);
    });
  });

  group('theme tokens', () {
    test('hex and rgb forms', () {
      expect(parseThemeColor('#fff'), const Color(0xFFFFFFFF));
      expect(parseThemeColor('#1a2'), const Color(0xFF11AA22));
      expect(parseThemeColor('#102030'), const Color(0xFF102030));
      expect(parseThemeColor('#10203040'), const Color(0x40102030)); // alpha is last
      expect(parseThemeColor('#1234'), const Color(0x44112233));
      expect(parseThemeColor('  #ABCDEF '), const Color(0xFFABCDEF));
      expect(parseThemeColor('rgb(1, 2, 3)'), const Color(0xFF010203));
      expect(parseThemeColor('rgba(255,0,0,0.5)')!.a, closeTo(0.5, 0.01));
      expect(parseThemeColor('rgba(255,0,0,1)'), const Color(0xFFFF0000));
    });

    test('anything else is refused', () {
      for (final bad in [
        '', 'red', '#12', '#12345', '#gggggg', 'rgb(256,0,0)', 'rgb(1 2 3)', 'rgba(1,2,3,2)', 'rgb(1,2)',
        'url(x)', 'var(--x)', '#fff; x', 'hsl(0,0%,0%)', 'transparent', '#${'f' * 40}',
      ]) {
        expect(parseThemeColor(bad), isNull, reason: bad);
      }
      expect(parseThemeColor(null), isNull);
    });

    test('unknown tokens and bad values are ignored', () {
      final c = validThemeTokens({'paper': '#000', 'ink': 'nope', 'unknown': '#fff', 'on-accent': 'rgb(1,2,3)'});
      expect(c.keys.toSet(), {'paper', 'on-accent'});
    });

    test('a missing token falls back to the default, per token and per mode', () {
      final t = tokensFromTheme(Brightness.light, {'muted': '#112233', 'ink-2': 'bad'});
      expect(t.muted, const Color(0xFF112233));
      expect(t.ink2, Tokens.light.ink2);
      expect(t.ok, Tokens.light.ok);
      final d = tokensFromTheme(Brightness.dark, null);
      expect(d.raised, Tokens.dark.raised);
    });

    test('the cursor stays on every theme', () {
      final t = tokensFromTheme(Brightness.light, {'accent': '#ff0000', 'accent-2': '#00ff00'});
      expect(t.cursor, Tokens.light.cursor);
      expect(t.cursor2, Tokens.light.cursor2);
      expect(tokensFromTheme(Brightness.dark, {'accent': '#ff0000'}).cursor, Tokens.dark.cursor);
    });

    test('usable needs the required tokens as valid colours in both modes', () {
      expect(themeUsable(_dusk, _dusk), isTrue);
      expect(themeUsable(_dusk, {..._dusk, 'paper': 'x'}), isFalse);
      expect(themeUsable(_dusk, const {}), isFalse);
      expect(themeUsable(const {}, const {}), isFalse);
    });

    test('ThemeData follows the tokens', () {
      final d = openPakLight({'paper': '#102030', 'accent': '#ff8800', 'ink': '#eeeeee', 'raised': '#223344'});
      expect(d.scaffoldBackgroundColor, const Color(0xFF102030));
      expect(d.colorScheme.primary, const Color(0xFFFF8800));
      expect(d.extension<Tokens>()!.raised, const Color(0xFF223344));
      expect(openPakLight().scaffoldBackgroundColor, openPakLight(const {}).scaffoldBackgroundColor);
    });
  });

  group('app-wide theme and preview', () {
    Future<RewardsThemeController> app(WidgetTester tester, Fake f, {GlobalKey<NavigatorState>? key}) async {
      final c = RewardsThemeController(f.api, navigatorKey: key);
      await tester.pumpWidget(
        RewardsThemeScope(
          controller: c,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => MaterialApp(
              navigatorKey: key,
              theme: c.light,
              darkTheme: c.dark,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => ThemePreviewHost(controller: c, child: child!),
              home: Builder(builder: (context) => Scaffold(body: Text('hi', style: TextStyle(color: tokensOf(context).muted)))),
            ),
          ),
        ),
      );
      return c;
    }

    testWidgets('a previewed theme re-colours the app, and stopping restores it', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final c = await app(tester, fake, key: key);
      Color bg() => Theme.of(tester.element(find.text('hi'))).scaffoldBackgroundColor;
      final before = bg();
      expect(find.byType(ThemePreviewBar), findsNothing);
      final it = RewardsItem.fromJson(item('theme-dusk', 'theme', price: 200));
      expect(await c.startPreview(it), isTrue);
      await tester.pumpAndSettle();
      expect(bg(), const Color(0xFF102030));
      expect(find.text('Previewing Dusk'), findsOneWidget);
      expect(find.text('Buy 200 pts'), findsOneWidget);
      expect(find.text('Stop preview'), findsOneWidget);
      await tester.tap(find.text('Stop preview'));
      await tester.pumpAndSettle();
      expect(bg(), before);
      expect(find.byType(ThemePreviewBar), findsNothing);
    });

    testWidgets('an owned theme offers Equip and equipping clears the preview', (tester) async {
      final c = await app(tester, fake);
      final it = RewardsItem.fromJson(item('theme-dusk', 'theme', more: {'owned': true}));
      await c.startPreview(it);
      await tester.pumpAndSettle();
      expect(find.text('Buy 100 pts'), findsNothing);
      await tester.tap(find.text('Equip'));
      await tester.pumpAndSettle();
      expect(fake.writes.single, 'POST /api/v1/me/rewards/equip {"slot":"theme","item":"theme-dusk"}');
      expect(c.preview, isNull);
    });

    testWidgets('an unusable theme is not applied', (tester) async {
      final c = await app(tester, fake);
      // The fake serves a usable theme for any id; ask for a controller whose api returns junk.
      final junk = RewardsThemeController(
        OpenPakApi(baseUrl: 'https://x.test', token: 't', client: MockClient((_) async => json({'id': 'a', 'name': 'A', 'light': {'paper': 'x'}, 'dark': {}}))),
      );
      expect(await junk.startPreview(RewardsItem.fromJson(item('a', 'theme'))), isFalse);
      expect(junk.preview, isNull);
      expect(c.preview, isNull);
    });

    testWidgets('the equipped theme loads, and sign-out clears it', (tester) async {
      final api = OpenPakApi(
        baseUrl: 'https://x.test',
        token: 't',
        client: MockClient((_) async => json({'theme': {'id': 'theme-dusk', 'name': 'Dusk', 'light': _dusk, 'dark': _dusk}})),
      );
      final c = RewardsThemeController(api);
      await c.load();
      expect(c.equipped?.name, 'Dusk');
      expect(c.light.scaffoldBackgroundColor, const Color(0xFF102030));
      expect(c.dark.scaffoldBackgroundColor, const Color(0xFF102030));
      c.clear();
      expect(c.equipped, isNull);
      expect(c.light.scaffoldBackgroundColor, openPakLight().scaffoldBackgroundColor);
    });

    testWidgets('a failing theme load keeps the default look silently', (tester) async {
      final c = RewardsThemeController(
        OpenPakApi(baseUrl: 'https://x.test', token: 't', client: MockClient((_) async => json({'code': 'rewards_unavailable'}, 503))),
      );
      await c.load();
      expect(c.equipped, isNull);
    });

    testWidgets('Preview on the shop applies the theme', (tester) async {
      final c = RewardsThemeController(fake.api);
      await pump(tester, controller: c);
      await tester.tap(find.text('Shop').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview').first);
      await tester.pumpAndSettle();
      expect(c.preview?.item.id, 'theme-dusk');
    });
  });
}

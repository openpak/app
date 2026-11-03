// Screenshot harness: pumps the real screens at phone size against a fake API
// and writes PNGs for a visual review. Not part of the normal suite (it lives
// in tool/, not test/); run it with
//
//   flock /tmp/openpak-build.lock flutter test tool/screenshots_test.dart
//
// Output: $SHOTS_OUT or ~/REPOS/Openpak/research/app/parity/<screen>-<lang>-<light|dark>.png
// (780x1688 for a 390x844 logical phone at devicePixelRatio 2; "-full" is the
// same width with a tall view so the whole page shows). Pictures come from a
// local server over files fetched once into $SHOTS_ASSETS (see _assets).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/account_details_page.dart';
import 'package:openpak/account_page.dart';
import 'package:openpak/activity_page.dart';
import 'package:openpak/api.dart';
import 'package:openpak/l10n.dart';
import 'package:openpak/operator_page.dart';
import 'package:openpak/rankings_page.dart';
import 'package:openpak/rewards_page.dart';
import 'package:openpak/rewards_theme.dart';
import 'package:openpak/sites_page.dart';
import 'package:openpak/support_page.dart';
import 'package:openpak/theme.dart';
import 'package:openpak/title_detail_page.dart';
import 'package:openpak/trophies_page.dart';

final _home = Platform.environment['HOME']!;
final _out = Platform.environment['SHOTS_OUT'] ?? '$_home/REPOS/Openpak/research/app/parity';
final _assets = Platform.environment['SHOTS_ASSETS'] ?? '$_home/REPOS/Openpak/scratch/parity/shots-tmp/assets';
final _flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '$_home/development/flutter';

late HttpServer _server;
late String _base;

// ---------------------------------------------------------------- fonts

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = await File(p).readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final mf = '$_flutterRoot/bin/cache/artifacts/material_fonts';
  await _font('Roboto', [for (final w in ['Regular', 'Medium', 'Bold', 'Light', 'Black']) '$mf/Roboto-$w.ttf']);
  await _font('MaterialIcons', ['$mf/MaterialIcons-Regular.otf']);
  // The UI face is declared in pubspec; load it explicitly so the harness does
  // not depend on the test runner's font manifest.
  await _font(uiFont, [
    for (final w in ['Medium', 'Bold', 'ExtraBold']) 'assets/fonts/MPLUSRounded1c-$w.ttf',
  ]);
  await _font('monospace', ['/usr/share/fonts/noto/NotoSansMono-Regular.ttf', '/usr/share/fonts/noto/NotoSansMono-Bold.ttf']);
  // Anything Roboto lacks (arrows, bullets, dingbats) falls back to Noto.
  await _font('Noto Sans', ['/usr/share/fonts/noto/NotoSans-Regular.ttf', '/usr/share/fonts/noto/NotoSansSymbols-Regular.ttf']);
}

// ------------------------------------------------------------ local pictures

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://127.0.0.1:${_server.port}';
  _server.listen((req) async {
    final path = req.uri.path;
    final key = path.substring(1).replaceAll('/', '_');
    var f = File('$_assets/$key');
    if (!f.existsSync()) {
      // Anything unknown (avatars, uploads, other previews) gets a stand-in.
      f = File('$_assets/account_rewards_preview_icon-tabby');
    }
    final bytes = await f.readAsBytes();
    req.response.headers.contentType = path.endsWith('.svg') ? ContentType('image', 'svg+xml') : ContentType('image', 'png');
    req.response.add(bytes);
    await req.response.close();
  });
}

// ------------------------------------------------------------------ fixtures

class Lang {
  const Lang(this.code);
  final String code;
  bool get de => code == 'de';
  String t(String en, String de) => this.de ? de : en;
}

http.Response _json(Object? body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

Map<String, Object?> _tile(String key, String name, String label, String img, String state, {Map<String, Object?> more = const {}}) => {
  'key': key,
  'name': label, // the server names a mission as it labels it
  'label': label,
  'description': '',
  'img': '/static/rewards/$img.png',
  'state': state,
  'percent': 40,
  'progress': '',
  'earned': 0,
  'single': true,
  'equipped': false,
  'complete': false,
  ...more,
};

Map<String, Object?> _item(String id, String kind, String name, String desc, {int? price = 100, Map<String, Object?> more = const {}}) => {
  'id': id,
  'kind': kind,
  'kind_label': switch (kind) { 'theme' => 'Theme', 'profile_icon' => 'Profile icon', _ => 'Badge' },
  'name': name,
  'description': desc,
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

const _ember = {
  'light': {
    'paper': '#fff4e6', 'paper-2': '#ffe8cc', 'raised': '#fffaf3', 'sunk': '#ffddb3',
    'ink': '#3b1f0a', 'ink-2': '#5a3513', 'muted': '#8a5a30', 'faint': '#b58d62',
    'line': '#f1d3ad', 'line-2': '#e3b988',
    'accent': '#e8590c', 'accent-2': '#f08c00', 'accent-weak': '#ffe0cc', 'accent-line': '#f5b58c', 'on-accent': '#ffffff',
  },
  'dark': {
    'paper': '#0e2a2d', 'paper-2': '#143a3e', 'raised': '#18444a', 'sunk': '#0a2023',
    'ink': '#e6fffa', 'ink-2': '#bfe9e2', 'muted': '#8bbab5', 'faint': '#5f8c88',
    'line': '#245b60', 'line-2': '#2f7077',
    'accent': '#ff922b', 'accent-2': '#ffa94d', 'accent-weak': '#3d3a24', 'accent-line': '#8a6a2a', 'on-accent': '#2a1200',
  },
};

Map<String, Object?> _rewards(Lang l) {
  final founder = {'kind': 'badge', 'id': 'badge-founder', 'name': 'Founder', 'img': '/account/rewards/preview/badge-founder'};
  return {
    'balance': 340,
    'frozen': false,
    'paused': false,
    'showcase_public': true,
    'today_points': 6,
    'today_cap': 8,
    'today_percent': 75,
    'cap_reached': false,
    'more': 2,
    'play_time': l.t('42 h 15 min', '42 Std. 15 Min.'),
    'owned': 7,
    'ready': 2,
    'affordable': 4,
    'next_kind': 'claim',
    'next_text': l.t('Rewards ready to claim: 2', 'Belohnungen zum Einlösen bereit: 2'),
    'badge': founder,
    'slots': [
      {'kind': 'badge', 'label': l.t('Badge', 'Abzeichen'), ...founder},
      {'kind': 'profile_icon', 'label': l.t('Profile icon', 'Profilsymbol'), 'id': 'icon-tabby', 'name': 'Tabby', 'img': '/account/rewards/preview/icon-tabby'},
      {'kind': 'theme', 'label': l.t('Theme', 'Design'), 'id': '', 'name': ''},
    ],
    'ready_tiles': [
      _tile('daily-play-30', 'daily', l.t('Play for 30 minutes today', 'Heute 30 Minuten spielen'), 'act-daily-play', 'ready',
          more: {'claim_text': l.t('Claim 10 points', '10 Punkte einlösen'), 'mission_id': 'daily-play-30', 'period': '2026-11-02', 'percent': 100, 'progress': '30 / 30 min', 'reward': l.t('+10 points', '+10 Punkte')}),
      _tile('weekly-networks', 'weekly', l.t('Play on 3 different networks this week', 'Diese Woche in 3 verschiedenen Netzwerken spielen'), 'act-weekly-networks', 'ready',
          more: {'claim_text': l.t('Claim 25 points', '25 Punkte einlösen'), 'mission_id': 'weekly-networks', 'period': '2026-W44', 'percent': 100, 'progress': '3 / 3', 'reward': l.t('+25 points', '+25 Punkte')}),
    ],
    'tiles': [
      _tile('kart', 'ladder', l.t('Mario Kart online sessions', 'Mehrspieler-Wettbewerbssitzungen in Mario Kart'), 'act-weekly-titles', 'progress', more: {
        'single': false,
        'pips': [true, true, false, false, false],
        'earned': 2,
        'percent': 55,
        'progress': l.t('11 / 20 sessions', '11 / 20 Sitzungen'),
        'reward': l.t('+50 points', '+50 Punkte'),
        'tiers': [
          {'finish': l.t('Wood', 'Holz'), 'img': '/account/rewards/preview/badge-kart-1', 'target': l.t('5 sessions', '5 Sitzungen'), 'points': l.t('10 points', '10 Punkte'), 'state': 'earned', 'ready': false},
          {'finish': 'Bronze', 'img': '/account/rewards/preview/badge-kart-10', 'target': l.t('10 sessions', '10 Sitzungen'), 'points': l.t('20 points', '20 Punkte'), 'state': 'earned', 'ready': false},
          {'finish': l.t('Silver', 'Silber'), 'img': '/account/rewards/preview/badge-kart-25', 'target': l.t('20 sessions', '20 Sitzungen'), 'points': l.t('30 points', '30 Punkte'), 'state': 'current', 'ready': false},
          {'finish': l.t('Gold', 'Gold'), 'target': l.t('50 sessions', '50 Sitzungen'), 'points': l.t('50 points', '50 Punkte'), 'state': 'locked', 'ready': false},
          {'finish': 'Platin', 'target': l.t('100 sessions', '100 Sitzungen'), 'state': 'locked', 'ready': false},
        ],
      }),
      _tile('friends', 'ladder', l.t('Make friends', 'Freundschaften schließen'), 'act-points', 'progress', more: {
        'single': false,
        'pips': [true, false, false],
        'earned': 1,
        'percent': 20,
        'progress': '3 / 10',
        'tiers': [
          {'finish': l.t('Bronze', 'Bronze'), 'img': '/account/rewards/preview/badge-first-friend', 'target': l.t('1 friend', '1 Freund'), 'state': 'earned', 'ready': false},
          {'finish': l.t('Silver', 'Silber'), 'target': l.t('10 friends', '10 Freunde'), 'state': 'current', 'ready': false},
          {'finish': l.t('Gold', 'Gold'), 'target': l.t('50 friends', '50 Freunde'), 'state': 'locked', 'ready': false},
        ],
      }),
      _tile('play-time', 'single', l.t('Play for 50 hours', 'Insgesamt 50 Stunden spielen'), 'act-play-time', 'progress',
          more: {'percent': 84, 'progress': '42 / 50 h', 'reward': l.t('+40 points', '+40 Punkte')}),
      _tile('checkin', 'single', l.t('Check in 7 days in a row', 'An 7 Tagen hintereinander spielen'), 'act-checkin', 'progress',
          more: {'percent': 43, 'progress': '3 / 7'}),
    ],
    'done': [
      _tile('first-online', 'single', l.t('First online session', 'Erste Online-Sitzung'), 'act-new-game', 'done', more: {'complete': true, 'progress': l.t('Done', 'Erledigt')}),
      _tile('new-game', 'single', l.t('Try a new game', 'Ein neues Spiel ausprobieren'), 'act-new-game', 'done', more: {'complete': true, 'progress': l.t('Done', 'Erledigt')}),
    ],
    'ledger': [
      {'img': '/static/rewards/act-play-time.png', 'title': l.t('Play time', 'Spielzeit'), 'sub': l.t('2 Nov', '2. Nov.'), 'delta': 2, 'points': '+2'},
      {'img': '/static/rewards/act-daily-play.png', 'title': l.t('Daily mission', 'Tagesmission'), 'sub': l.t('1 Nov', '1. Nov.'), 'delta': 10, 'points': '+10'},
      {'img': '/static/rewards/act-points.png', 'title': l.t('Redeemed: Tabby', 'Eingelöst: Tabby'), 'sub': l.t('30 Oct', '30. Okt.'), 'delta': -80, 'points': '-80'},
    ],
    'shop': [
      {
        'kind': 'badge',
        'label': l.t('Badges', 'Abzeichen'),
        'wide': false,
        'items': [
          _item('badge-launch-season', 'badge', l.t('Launch season', 'Startsaison'), l.t('Worn by early players.', 'Von frühen Spielern getragen.'), price: 100, more: {'limited': true}),
        ],
      },
      {
        'kind': 'profile_icon',
        'label': l.t('Profile icons', 'Profilsymbole'),
        'wide': false,
        'items': [
          _item('icon-pak', 'profile_icon', l.t('Pak Original', 'Pak Original'), l.t('The mascot.', 'Das Maskottchen.'), price: 150),
          _item('icon-ember-fox', 'profile_icon', l.t('Ember Fox', 'Glutfuchs'), l.t('A warm fox.', 'Ein warmer Fuchs.'), price: 150),
        ],
      },
      {
        'kind': 'theme',
        'label': l.t('Themes', 'Designs'),
        'wide': true,
        'items': [
          _item('theme-harbor', 'theme', 'Harbor', l.t('Deep blue and brass.', 'Tiefblau und Messing.'), price: 400, more: {'need': 60, 'affordable': false}),
          _item('theme-ember', 'theme', 'Ember', l.t('Warm orange on dark teal.', 'Warmes Orange auf dunklem Petrol.'), price: 450, more: {'need': 110, 'affordable': false}),
          _item('theme-moss', 'theme', 'Moss', l.t('Calm greens.', 'Ruhige Grüntöne.'), price: 400, more: {'need': 60, 'affordable': false}),
        ],
      },
    ],
    'upcoming': [
      _item('badge-winter-2026', 'badge', 'Winter 2026', '', price: 100, more: {'limited': true, 'soon': true, 'when': l.t('Coming 1 Dec', 'Ab 1. Dez.')}),
      _item('badge-new-year-2027', 'badge', l.t('New Year 2027', 'Neujahr 2027'), '', price: 150, more: {'limited': true, 'soon': true, 'when': l.t('Coming 28 Dec', 'Ab 28. Dez.')}),
    ],
    'mine': [
      {
        'kind': 'badge',
        'label': l.t('Badges', 'Abzeichen'),
        'wide': false,
        'tiles': [
          _tile('kart', 'ladder', l.t('Mario Kart online sessions', 'Mehrspieler-Wettbewerbssitzungen in Mario Kart'), 'act-weekly-titles', 'earned',
              more: {'single': false, 'pips': [true, true, false, false, false], 'earned': 2, 'equip_item': 'badge-kart-10'}),
        ],
        'items': [
          _item('badge-founder', 'badge', 'Founder', l.t('An early supporter.', 'Früher Unterstützer.'), more: {'owned': true, 'equipped': true}),
          _item('badge-first-friend', 'badge', 'First Friend', l.t('Added your first friend.', 'Den ersten Freund hinzugefügt.'), more: {'owned': true}),
        ],
      },
      {
        'kind': 'profile_icon',
        'label': l.t('Profile icons', 'Profilsymbole'),
        'wide': false,
        'items': [_item('icon-tabby', 'profile_icon', 'Tabby', '', more: {'owned': true, 'equipped': true})],
      },
      {
        'kind': 'theme',
        'label': l.t('Themes', 'Designs'),
        'wide': true,
        'items': [
          _item('theme-graphite', 'theme', 'Graphite', l.t('Quiet greys.', 'Ruhiges Grau.'), more: {'owned': true}),
          _item('theme-ember', 'theme', 'Ember', l.t('Warm orange on dark teal.', 'Warmes Orange auf dunklem Petrol.'), more: {'owned': true}),
        ],
      },
    ],
  };
}

Map<String, Object?> _ticket(int id, String subject, String status, String cat, {List<Map<String, Object?>>? thread}) => {
  'id': id,
  'subject': subject,
  'category': cat,
  'status': status,
  'messages': thread?.length ?? 2,
  'created_at': '2026-11-01T10:00:00Z',
  'updated_at': '2026-11-02T10:00:00Z',
  if (thread != null) 'thread': thread,
};

Map<String, Object?> _msg(int id, String from, String body, {Map<String, Object?>? attachment}) => {
  'id': id,
  'from': from,
  'body': body,
  'created_at': '2026-11-01T10:0$id:00Z',
  'attachment': attachment,
};

Map<String, Object?> _ranking(Lang l) => {
  'boards': [
    {'id': 'a', 'label': l.t('Luigi Circuit (150cc)', 'Luigi-Circuit (150ccm)')},
    {'id': 'b', 'label': l.t('Mushroom Gorge', 'Pilzschlucht'), 'unit': 'ms'},
  ],
  'board': 'a',
  'label': l.t('Luigi Circuit (150cc)', 'Luigi-Circuit (150ccm)'),
  'entries': [
    for (var i = 0; i < 8; i++)
      {
        'rank': i + 1,
        'name': ['Ann', 'Bob', 'Chewbacca', 'Dagmar-Wunderlich', 'Erik', 'Fenja', 'Gustav', 'Hanne'][i],
        'value': 61000 + i * 900,
        'display': '1:0${1 + (i * 9) ~/ 10}.${(i * 137 + 20) % 1000}'.replaceAll(RegExp(r'\.(\d)$'), '.00\$1'),
        'region': ['EU', 'NA', 'EU', 'EU', 'JP', 'EU', 'NA', 'EU'][i],
        'avatar': '/avatar/u$i.png',
        'account_id': 'u$i',
        if (i == 2) 'me': true,
      },
  ],
  'around': [
    {'rank': 40, 'name': 'Leia', 'value': 90000, 'display': '1:30.000', 'me': true},
  ],
  'total': 120,
  'offset': 0,
  'limit': 8,
};

/// One router for every endpoint the screens call.
class Fake {
  Fake(this.lang);
  final Lang lang;
  bool discordLinked = true;
  Map<String, Object?>? equippedTheme;
  late final api = OpenPakApi(baseUrl: _base, token: 't', client: MockClient(_handle));

  Future<http.Response> _handle(http.Request req) async {
    final l = lang;
    final path = req.url.path.replaceFirst('/api/v1', '');
    switch (path) {
      case '/me' when req.method == 'GET':
        return _json({
          'account_id': 'a1',
          'display_name': l.t('Leia Organa', 'Leia Organa-Bundesverdienstkreuz'),
          'handle': 'leia',
          'friend_codes': [
            {'kind': 'switch', 'label': 'Switch', 'code': 'SW-1234-5678-9012'},
            {'kind': 'nnid', 'label': 'Wii U', 'code': 'LeiaO'},
          ],
          'country': 'DE',
          'birthday': '1990-05-04',
          'avatar_url': '/avatar/a1.png',
          'linked_platforms': [
            {'namespace': 'switch'},
            {'namespace': 'wiiu'},
            {'namespace': '3ds'},
            {'namespace': 'wfc'},
          ],
          'email': 'leia@example.org',
          'email_verified': true,
          'two_factor_enabled': true,
          'motto': l.t('May the fourth', 'Möge die Macht'),
          'bio': l.t('Rebel, senator, kart enthusiast.', 'Rebellin, Senatorin und begeisterte Kart-Fahrerin.'),
        });
      case '/me/sessions':
        return _json({
          'sessions': [
            {'id': 's1', 'user_agent': 'Firefox on Linux', 'created_at': '2026-11-01T10:00:00Z', 'expires_at': '2026-12-01T10:00:00Z', 'current': true},
            {'id': 's2', 'created_at': '2026-10-20T08:00:00Z', 'expires_at': '2026-11-19T08:00:00Z'},
          ],
        });
      case '/me/friends':
        return _json({
          'friends': [
            {'account_id': 'f1', 'display_name': 'Han', 'online': true},
            {'account_id': 'f2', 'display_name': 'Chewie', 'online': true},
            {'account_id': 'f3', 'display_name': 'Lando', 'online': false},
          ],
        });
      case '/me/friends/requests':
        return _json({
          'incoming': [
            {'account_id': 'r1', 'display_name': 'Rey'},
          ],
          'outgoing': [],
        });
      case '/pakka/state':
        return _json({'available': true, 'eligible': true, 'consent': true});
      case '/me/discord':
        return _json({'configured': true, 'linked': discordLinked, if (discordLinked) 'username': 'leia_organa'});
      case '/me/rewards':
        return _json(_rewards(l));
      case '/me/rewards/theme':
        return _json({'theme': equippedTheme});
      case '/me/trophies':
        return _json({
          'heading': 'leia_psn',
          'linked': true,
          'stats': [
            {'key': 'trophies.total', 'value': '57', 'n': 57},
            {'key': 'trophies.points', 'value': '4,180', 'n': 4180},
            {'key': 'trophies.platinum', 'value': '2', 'n': 2},
            {'key': 'trophies.gold', 'value': '9', 'n': 9},
            {'key': 'trophies.silver', 'value': '17', 'n': 17},
            {'key': 'trophies.bronze', 'value': '29', 'n': 29},
          ],
          'rows': [
            {'title': 'Uncharted: Drake\'s Fortune', 'sub': '2026-10-21', 'value': '18', 'percent': 72},
            {'title': l.t('The Last of Us', 'The Last of Us Remastered'), 'sub': '2026-10-11', 'value': '24', 'percent': 55},
            {'title': 'Demon\'s Souls', 'sub': '2026-09-30', 'value': '15', 'percent': 31},
            {'title': 'NPWR00001_00', 'sub': '2026-10-01', 'value': '3', 'percent': -1},
          ],
        });
      case '/me/activity':
        return _json({
          'titles': [
            {'network': 'switch', 'title_id': '01', 'title': 'Mario Kart 8 Deluxe', 'sessions': 38, 'seconds': 90000, 'first_played': '2026-08-01T10:00:00Z', 'last_played': '2026-11-02T10:00:00Z'},
            {'network': 'wiiu', 'title_id': '02', 'title': 'Splatoon', 'sessions': 12, 'seconds': 36000, 'last_played': '2026-10-28T10:00:00Z'},
            {'network': 'wfc', 'title_id': '03', 'title': 'Mario Kart Wii', 'sessions': 9, 'seconds': 14400, 'last_played': '2026-10-20T10:00:00Z'},
            {'network': 'switch', 'title_id': '04', 'title': l.t('Super Smash Bros. Ultimate', 'Super Smash Bros. Ultimate Mehrspieler-Wochenende'), 'sessions': 4, 'seconds': 3600, 'last_played': '2026-10-05T10:00:00Z'},
            {'network': 'wfc', 'sessions': 1, 'seconds': 600, 'last_played': '2026-09-05T10:00:00Z'},
          ],
          'total_seconds': 144600,
          'sessions': 64,
          'networks': ['switch', 'wiiu', 'wfc'],
        });
      case '/rankings':
        return _json({
          'games': [
            {'slug': 'mkw', 'name': 'Mario Kart Wii', 'console': 'Wii', 'boards': 32},
            {'slug': 'mk8dx', 'name': 'Mario Kart 8 Deluxe', 'console': 'Switch', 'boards': 48},
            {'slug': 'mk7', 'name': 'Mario Kart 7', 'console': '3DS', 'boards': 32},
            {'slug': 'mk8', 'name': 'Mario Kart 8', 'console': 'Wii U', 'boards': 1},
            {'slug': 'mkds', 'name': 'Mario Kart DS', 'console': 'DS', 'boards': 2},
          ],
        });
      case '/companion/titles/mkw/rankings':
        return _json(_ranking(l));
      case '/companion/titles/mkw':
        return _json({'slug': 'mkw', 'name': 'Mario Kart Wii', 'console': 'Wii', 'status': 'live', 'title_id': 'RMC', 'features': ['rankings', 'listings', 'stats']});
      case '/companion/titles/mkw/listings':
        return _json({'stats': [{'key': 'companion.listings.open', 'value': '3', 'n': 3}], 'rows': [], 'linked': true});
      case '/companion/titles/mkw/stats':
        return _json({
          'stats': [{'key': 'activity.total', 'value': '2 h', 'n': 2}, {'key': 'activity.sessions', 'value': '9', 'n': 9}],
          'rows': [{'title': 'Luigi Circuit', 'sub': '1:01.234', 'value': '#3', 'percent': 80}],
          'linked': true,
        });
      case '/me/tickets' when req.method == 'GET':
        return _json({
          'tickets': [
            _ticket(7, l.t('Cannot sign in on my Switch', 'Anmeldung auf der Switch nicht möglich'), 'waiting', 'switch'),
            _ticket(6, l.t('Friend code does not work', 'Freundescode funktioniert nicht'), 'open', 'account'),
            _ticket(4, l.t('Save upload fails', 'Hochladen des Spielstands schlägt fehl'), 'closed', 'saves'),
          ],
          'categories': ['account', 'network', 'switch', 'wiiu-3ds', 'emulator', 'saves', 'app', 'other'],
          'attachments': true,
        });
      case '/me/tickets/7':
        return _json(_ticket(7, l.t('Cannot sign in on my Switch', 'Anmeldung auf der Switch nicht möglich'), 'waiting', 'switch', thread: [
          _msg(1, 'you', l.t('Since the update my Switch says 2124-0041 when I open the shop.', 'Seit dem Update zeigt meine Switch 2124-0041, sobald ich den Shop öffne.')),
          _msg(2, 'staff', l.t('Thanks. Please restart the console once and try again; if it still fails, send the screenshot.', 'Danke. Bitte starte die Konsole einmal neu und versuche es erneut; falls es weiter fehlschlägt, schicke den Screenshot.'),
              attachment: {'name': 'steps.png', 'size': 20480, 'url': '/api/v1/me/tickets/7/attachments/2'}),
          _msg(3, 'you', l.t('That fixed it, thank you!', 'Das hat geholfen, vielen Dank!')),
        ]));
      case '/me/operator':
        return _json({
          'available': true,
          'in_review': false,
          'roles': ['photon', 'turn', 'stun', 'npln_relay'],
          'max_servers': 2,
          'terms_url': 'https://openpak.org/operators',
          'requirements': {
            'node_cores': 8, 'node_ram_gb': 16, 'node_disk_gb': 160,
            'server_cores': 2, 'server_ram_gb': 4, 'server_bandwidth_mbps': 500, 'availability_pct': 99,
          },
          'locations': [
            {'code': 'de-fra', 'country': 'DE', 'city': 'Frankfurt'},
            {'code': 'kr-sel', 'country': 'KR', 'city': 'Seoul'},
          ],
          'applications': [
            {
              'id': 4, 'status': 'info', 'country': 'DE', 'city': 'Frankfurt',
              'admin_note': l.t('Which hosting provider is this?', 'Bei welchem Hosting-Anbieter läuft der Server?'),
              'servers': [
                {'cores': 4, 'ram_gb': 8, 'disk_gb': 200, 'disk_ssd': true, 'bandwidth_mbps': 1000, 'ipv6': true, 'roles': ['turn', 'stun']},
              ],
            },
            {'id': 2, 'status': 'rejected', 'country': 'US', 'city': 'Dallas', 'admin_note': l.t('Too small', 'Zu klein dimensioniert')},
          ],
        });
    }
    if (path.startsWith('/themes/')) {
      return _json({'id': 'theme-ember', 'name': 'Ember', ..._ember});
    }
    return _json({'error': 'not found', 'code': 'not_found'}, 404);
  }
}

// -------------------------------------------------------------- the harness

final _boundary = GlobalKey();

Future<void> _settle(WidgetTester tester) async {
  // Real time for the local picture server and the codec, fake time for frames.
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _save(WidgetTester tester, String name) async {
  await _settle(tester);
  await tester.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_out).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(data!.buffer.asUint8List());
  });
  expect(tester.takeException(), isNull, reason: name);
}

typedef _Build = Widget Function(OpenPakApi api, Lang l);
typedef _Act = Future<void> Function(WidgetTester tester, AppLocalizations l, Fake fake);

Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    // A lazy list has not built it yet.
    final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.scrollUntilVisible(f, 300, scrollable: page, maxScrolls: 60);
  }
  await tester.ensureVisible(f.first);
  await tester.tap(f.first);
  await _settle(tester);
}

/// Pumps [build] for each language and mode, runs [act], writes the PNGs.
void _screen(
  String name,
  _Build build, {
  _Act? act,
  bool full = true,
  bool phone = true,
  Map<String, Object?>? theme,
  bool controller = false,
  Future<void> Function(RewardsThemeController c, Fake fake)? prepare,
  double fullHeight = 1800,
}) {
  for (final lang in const ['en', 'de']) {
    for (final dark in const [false, true]) {
      final mode = dark ? 'dark' : 'light';
      for (final tall in [if (phone) false, if (full) true]) {
        testWidgets('$name $lang $mode${tall ? ' full' : ''}', (tester) async {
          HttpOverrides.global = null; // flutter_test refuses real sockets by default
          final l = Lang(lang);
          final fake = Fake(l);
          if (theme != null) fake.equippedTheme = {'id': 'theme-ember', 'name': 'Ember', ...theme};
          tester.view.physicalSize = Size(780, tall ? fullHeight * 2 : 1688);
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          final loc = lookupAppLocalizations(Locale(lang));
          RewardsThemeController? c;
          final navKey = GlobalKey<NavigatorState>();
          if (controller) {
            c = RewardsThemeController(fake.api, navigatorKey: navKey);
            if (theme != null) await tester.runAsync(c.load);
            if (prepare != null) await tester.runAsync(() => prepare(c!, fake));
          }
          Widget app() => MaterialApp(
            navigatorKey: navKey,
            debugShowCheckedModeBanner: false,
            theme: c?.light ?? openPakLight(),
            darkTheme: c?.dark ?? openPakDark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            locale: Locale(lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: c == null ? null : (context, child) => ThemePreviewHost(controller: c!, child: child!),
            home: build(fake.api, l),
          );
          Widget root = RepaintBoundary(key: _boundary, child: c == null ? app() : ListenableBuilder(listenable: c, builder: (_, _) => app()));
          if (c != null) root = RewardsThemeScope(controller: c, child: root);
          await tester.pumpWidget(root);
          await _settle(tester);
          if (act != null) await act(tester, loc, fake);
          if (tall) {
            // The act may have scrolled to its target; the full page starts at the top.
            for (final e in find.byType(Scrollable).evaluate()) {
              final st = (e as StatefulElement).state as ScrollableState;
              if (st.axisDirection == AxisDirection.down) st.position.jumpTo(0);
            }
          }
          await _save(tester, '$name${tall ? '-full' : ''}-$lang-$mode');
          // Let timers (toasts, ripples, image retries) finish before teardown.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 40)); // keep-alive timers of the picture connections
        });
      }
    }
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    await _startServer();
    // NetworkImage keeps one shared HttpClient, created by the first load. Make
    // it here, outside any test's fake clock, or its idle timer fails test one.
    HttpOverrides.global = null;
    final warm = Completer<void>();
    NetworkImage('$_base/warm.png').resolve(ImageConfiguration.empty).addListener(
      ImageStreamListener((_, _) => warm.complete(), onError: (_, _) => warm.complete()),
    );
    await warm.future;
  });
  tearDownAll(() => _server.close(force: true));

  // ---- account hub and details
  _screen('account-hub', (api, l) => AccountPage(api: api, onSignedOut: () async {}));
  _screen('account-linked', (api, l) => AccountPage(api: api, onSignedOut: () async {}), full: false, act: (tester, l, fake) async {
    final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.scrollUntilVisible(find.text('leia_organa'), 200, scrollable: page);
    await tester.drag(page, const Offset(0, 260)); // show the whole Linked card, not only its last row
    await _settle(tester);
  });
  _screen('account-sessions', (api, l) => AccountPage(api: api, onSignedOut: () async {}), full: false, act: (tester, l, fake) async {
    final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.scrollUntilVisible(find.text(l.accountThisDevice), 200, scrollable: page);
    await tester.drag(page, const Offset(0, -120));
    await _settle(tester);
  });
  _screen('account-details', (api, l) => AccountDetailsPage(api: api, account: Account(id: 'a1', displayName: l.t('Leia Organa', 'Leia Organa-Bundesverdienstkreuz'), country: 'DE', birthday: '1990-05-04', handle: 'leia')));

  // ---- rewards
  Future<void> tab(WidgetTester tester, String label) => _tap(tester, find.text(label));
  _screen('rewards-missions', (api, l) => RewardsPage(api: api));
  _screen('rewards-ladder-tiers', (api, l) => RewardsPage(api: api), full: false, act: (tester, l, fake) async {
    await _tap(tester, find.textContaining(l.localeName == 'de' ? 'Mehrspieler-Wettbewerbssitzungen' : 'Mario Kart online'));
  });
  _screen('rewards-shop', (api, l) => RewardsPage(api: api), act: (tester, l, fake) => tab(tester, l.rewardsTabShop));
  _screen('rewards-shop-buy-dialog', (api, l) => RewardsPage(api: api), full: false, act: (tester, l, fake) async {
    await tab(tester, l.rewardsTabShop);
    await _tap(tester, find.text(l.localeName == 'de' ? 'Startsaison' : 'Launch season'));
  });
  _screen('rewards-shop-soon', (api, l) => RewardsPage(api: api), full: false, act: (tester, l, fake) async {
    await tab(tester, l.rewardsTabShop);
    final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.scrollUntilVisible(find.textContaining(l.localeName == 'de' ? 'Ab 28. Dez.' : 'Coming 28 Dec'), 300, scrollable: page);
    await tester.drag(page, const Offset(0, -200));
    await _settle(tester);
  });
  _screen('rewards-myitems', (api, l) => RewardsPage(api: api), act: (tester, l, fake) => tab(tester, l.rewardsTabCollection));
  _screen('rewards-settings', (api, l) => RewardsPage(api: api), act: (tester, l, fake) => tab(tester, l.rewardsTabSettings));
  _screen('rewards-themed', (api, l) => RewardsPage(api: api), theme: _ember, controller: true);
  _screen('rewards-preview-bar', (api, l) => RewardsPage(api: api), controller: true, full: false,
      prepare: (c, fake) async {
        final it = RewardsItem.fromJson(_item('theme-ember', 'theme', 'Ember', '', price: 450));
        await c.startPreview(it);
      },
      act: (tester, l, fake) => tab(tester, l.rewardsTabShop));
  _screen('rewards-preview-bar-owned', (api, l) => RewardsPage(api: api), controller: true, full: false,
      prepare: (c, fake) async {
        final it = RewardsItem.fromJson(_item('theme-ember', 'theme', 'Ember', '', price: 240, more: {'owned': true}));
        await c.startPreview(it);
      });

  // ---- play
  _screen('trophies', (api, l) => TrophiesPage(api: api));
  _screen('activity', (api, l) => ActivityPage(api: api));
  _screen('rankings-hub', (api, l) => RankingsPage(api: api));
  _screen('rankings-board', (api, l) => RankingsPage(api: api), act: (tester, l, fake) => _tap(tester, find.text('Mario Kart Wii')));
  _screen('title-detail', (api, l) => TitleDetailPage(
    api: api,
    item: CatalogItem(id: '1', kind: 'title', name: 'Mario Kart Wii', console: 'Wii', status: 'live', category: 'Racing', backend: 'wfc', verseUrl: 'https://verse.openpak.org/communities/1', notes: l.t('Online races, rankings and friend rooms.', 'Online-Rennen, Ranglisten und Freundesräume.')),
    companion: CompanionTitle(slug: 'mkw', name: 'Mario Kart Wii', console: 'Wii', features: const ['rankings', 'listings', 'stats']),
  ));
  _screen('title-detail-rankings', (api, l) => TitleDetailPage(
    api: api,
    item: CatalogItem(id: '1', kind: 'title', name: 'Mario Kart Wii', console: 'Wii', status: 'live'),
    companion: CompanionTitle(slug: 'mkw', name: 'Mario Kart Wii', console: 'Wii', features: const ['rankings', 'listings', 'stats']),
  ), full: false, act: (tester, l, fake) => _tap(tester, find.descendant(of: find.byType(TabBar), matching: find.text(l.localeName == 'de' ? 'Ranglisten' : 'Rankings'))));
  _screen('sites', (api, l) => SitesPage(api: api));

  // ---- help
  _screen('support-list', (api, l) => SupportPage(api: api));
  _screen('support-ticket', (api, l) => TicketPage(api: api, ticket: Ticket.fromJson(_ticket(7, l.t('Cannot sign in on my Switch', 'Anmeldung auf der Switch nicht möglich'), 'waiting', 'switch'))));
  _screen('support-new', (api, l) => SupportPage(
    api: api,
    subject: l.t('Kart crashes at the start', 'Kart stürzt beim Spielstart ab'),
    category: 'switch',
    message: l.t('The game closes right after the logo.', 'Das Spiel schließt sich direkt nach dem Logo.'),
  ), act: (tester, l, fake) async {
    final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.drag(page, const Offset(0, -3000));
    await _settle(tester);
  });
  _screen('operator', (api, l) => OperatorPage(api: api));
}

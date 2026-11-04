import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/activity_page.dart';
import 'package:openpak/api.dart';
import 'package:openpak/l10n.dart';
import 'package:openpak/open_sites.dart';
import 'package:openpak/rankings_page.dart';
import 'package:openpak/sites_page.dart';
import 'package:openpak/theme.dart';
import 'package:openpak/title_detail_page.dart';
import 'package:openpak/trophies_page.dart';

import 'localized.dart';

OpenPakApi _api(
  Map<String, Object> routes, {
  List<String>? seen,
  String? token = 't',
}) => OpenPakApi(
  baseUrl: 'https://openpak.test',
  token: token,
  client: MockClient((req) async {
    seen?.add('${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}');
    final body = routes[req.url.path.replaceFirst('/api/v1', '')];
    if (body == null) {
      return http.Response(
        jsonEncode({'error': 'not found', 'code': 'not_found'}),
        404,
      );
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

Finder tab(String t) =>
    find.descendant(of: find.byType(TabBar), matching: find.text(t));

Widget _app(Widget home) => localizedApp(theme: openPakLight(), home: home);

final _ranking = {
  'boards': [
    {'id': 'a', 'label': 'Course A'},
    {'id': 'b', 'label': 'Course B', 'unit': 'ms'},
  ],
  'board': 'a',
  'label': 'Course A',
  'entries': [
    {
      'rank': 1,
      'name': 'Ann',
      'value': 61000,
      'display': '1:01.000',
      'region': 'EU',
      'avatar': '/avatar/x.png',
      'account_id': 'u1',
    },
    {
      'rank': 2,
      'name': 'Bob',
      'value': 62000,
      'display': '1:02.000',
      'me': true,
    },
  ],
  'around': [
    {
      'rank': 40,
      'name': 'Me',
      'value': 90000,
      'display': '1:30.000',
      'me': true,
    },
  ],
  'total': 50,
  'offset': 0,
  'limit': 25,
};

void main() {
  group('parsing', () {
    test('trophies card', () async {
      final api = _api({
        '/me/trophies': {
          'heading': 'psn_user',
          'linked': true,
          'stats': [
            {'key': 'trophies.total', 'value': '3', 'n': 3},
            {'key': 'trophies.gold', 'value': '1', 'n': 1},
          ],
          'rows': [
            {
              'title': 'NPWR00001_00',
              'sub': '2026-10-01',
              'value': '3',
              'percent': -1,
            },
          ],
        },
      });
      final c = await api.trophies();
      expect(c.linked, isTrue);
      expect(c.heading, 'psn_user');
      expect(c.stats.map((s) => s.n), [3, 1]);
      expect(c.rows.single.percent, -1);
    });

    test('activity', () async {
      final api = _api({
        '/me/activity': {
          'titles': [
            {
              'network': 'switch',
              'title_id': '01',
              'title': 'Outbound',
              'icon': true,
              'sessions': 2,
              'seconds': 7200,
              'first_played': '2026-10-01T10:00:00Z',
              'last_played': '2026-10-02T10:00:00Z',
            },
            {
              'network': 'wiiu',
              'title_id': '02',
              'title': '',
              'sessions': 1,
              'seconds': 600,
              'last_played': '2026-10-05T10:00:00Z',
            },
          ],
          'total_seconds': 7800,
          'sessions': 3,
          'networks': ['switch', 'wiiu'],
        },
      });
      final a = await api.playActivity();
      expect(a.totalSeconds, 7800);
      expect(a.newestFirst.first.titleId, '02'); // newest first
      expect(a.titles.first.last!.year, 2026);
    });

    test('rankings games, companion titles, ranking page, cards', () async {
      final seen = <String>[];
      final api = _api({
        '/rankings': {
          'games': [
            {
              'slug': 'mario-kart-wii',
              'name': 'Mario Kart Wii',
              'console': 'Wii',
              'boards': 2,
            },
          ],
        },
        '/companion/titles': {
          'titles': [
            {
              'slug': 'mario-kart-wii',
              'name': 'Mario Kart Wii',
              'console': 'Wii',
              'status': 'live',
              'features': ['rankings', 'stats'],
            },
          ],
        },
        '/companion/titles/mario-kart-wii': {
          'slug': 'mario-kart-wii',
          'name': 'Mario Kart Wii',
          'console': 'Wii',
          'status': 'live',
          'title_id': 'RMC',
          'features': ['rankings'],
        },
        '/companion/titles/mario-kart-wii/rankings': _ranking,
        '/companion/titles/mario-kart-wii/stats': {
          'stats': [],
          'rows': [],
          'linked': false,
        },
        '/companion/titles/mario-kart-wii/listings': {
          'stats': [
            {'key': 'companion.listings.open', 'value': '2', 'n': 2},
          ],
          'rows': [],
          'linked': true,
        },
      }, seen: seen);
      expect((await api.rankedGames()).single.boards, 2);
      final titles = await api.companionTitles();
      expect(titles.single.features, ['rankings', 'stats']);
      expect((await api.companionTitle('mario-kart-wii')).titleId, 'RMC');
      final r = await api.companionRankings(
        'mario-kart-wii',
        board: 'b',
        offset: 25,
      );
      expect(
        seen.last,
        '/api/v1/companion/titles/mario-kart-wii/rankings?board=b&offset=25',
      );
      expect(r.boards[1].unit, 'ms');
      expect(r.entries[1].me, isTrue);
      expect(r.entries[0].avatar, '/avatar/x.png');
      expect(r.entries[1].avatar, isNull);
      expect(r.around.single.rank, 40);
      expect(r.hasPrev, isFalse);
      expect(r.hasNext, isTrue);
      expect((await api.companionStats('mario-kart-wii')).linked, isFalse);
      expect((await api.companionListings('mario-kart-wii')).stats.single.n, 2);
    });

    test('zero times and missing fields do not break', () {
      final a = PlayActivity.fromJson({
        'titles': [
          {'last_played': '0001-01-01T00:00:00Z'},
        ],
      });
      expect(a.titles.single.last, isNull);
      expect(RankingPage.fromJson({}).hasNext, isFalse);
      expect(CompanionCard.fromJson({}).linked, isFalse);
    });
  });

  group('logic', () {
    test('tabs: overview plus only what the server lists', () {
      expect(companionTabs([]), isEmpty);
      expect(companionTabs(['rankings']), ['overview', 'rankings']);
      expect(
        companionTabs(['rankings', 'listings', 'stats', 'bogus', 'rankings']),
        ['overview', 'rankings', 'listings', 'stats'],
      );
    });

    test('companion matches a catalogue title by name and console', () {
      final all = [
        CompanionTitle(
          slug: 'a-wii',
          name: 'A',
          console: 'Wii',
          features: const ['rankings'],
        ),
        CompanionTitle(
          slug: 'a-switch',
          name: 'A',
          console: 'Switch',
          features: const ['stats'],
        ),
      ];
      expect(
        companionFor(
          all,
          CatalogItem(id: '1', kind: 'title', name: 'a', console: 'Switch'),
        )!.slug,
        'a-switch',
      );
      expect(
        companionFor(
          all,
          CatalogItem(id: '1', kind: 'title', name: 'A', console: 'DS'),
        ),
        isNull,
      );
    });

    test('sites mapping follows the website', () {
      expect(siteFor('Splatoon', 'Wii U')!.key, 'opensplat');
      expect(
        siteFor('Mario Kart 8 Deluxe', 'Switch')!.url,
        'https://kart.openpak.org',
      );
      expect(siteFor('Super Mario Maker', '3DS')!.name, 'OpenMaker');
      expect(siteFor('Splatoon', 'Switch'), isNull);
      expect(siteFor('Outbound', 'Switch'), isNull);
      expect(openSites.map((s) => s.key), [
        'opensplat',
        'openkart',
        'openmaker',
        'openverse',
      ]);
      expect(openSites.first.mark, '/static/sites/opensplat.svg');
    });

    test('rankings hub groups by console and searches', () {
      final g = [
        RankedGame(slug: 'b', name: 'Beta', console: 'Wii'),
        RankedGame(slug: 'a', name: 'Alpha', console: 'Wii'),
        RankedGame(slug: 'c', name: 'Gamma', console: '3DS'),
      ];
      final m = groupByConsole(g);
      expect(m.keys, ['3DS', 'Wii']);
      expect(m['Wii']!.map((x) => x.name), ['Alpha', 'Beta']);
      expect(groupByConsole(g, 'gam').keys, ['3DS']);
    });

    test(
      'rankings hub lists games nobody has scored in, after the scored ones',
      () {
        final g = [
          RankedGame.fromJson({
            'slug': 'a',
            'name': 'Alpha',
            'console': 'Switch',
            'boards': 2,
            'has_scores': false,
            'board_names': ['Time trial', 'Board 2'],
          }),
          RankedGame.fromJson({
            'slug': 'z',
            'name': 'Zeta',
            'console': 'Switch',
            'boards': 1,
            'has_scores': true,
          }),
          // An older server sends no flag: the game has scores.
          RankedGame.fromJson({
            'slug': 'o',
            'name': 'Old',
            'console': 'Switch',
          }),
        ];
        expect(g[0].hasScores, isFalse);
        expect(g[0].boardNames, ['Time trial', 'Board 2']);
        expect(g[2].hasScores, isTrue);
        expect(groupByConsole(g)['Switch']!.map((x) => x.name), [
          'Old',
          'Zeta',
          'Alpha',
        ]);
        expect(
          RankingPage.fromJson({
            'no_scores': true,
            'boards': [
              {'id': '0', 'label': 'Time trial', 'no_scores': true},
            ],
          }).noScores,
          isTrue,
        );
      },
    );

    testWidgets(
      'activity card: shares of the most played, unknown title named',
      (tester) async {
        late AppLocalizations l;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (c) {
                l = c.l10n;
                return const SizedBox();
              },
            ),
          ),
        );
        final c = activityCard(
          l,
          PlayActivity(
            totalSeconds: 3900,
            sessions: 2,
            titles: [
              ActivityTitle(
                network: 'switch',
                title: 'Outbound',
                sessions: 1,
                seconds: 3600,
                last: DateTime.utc(2026, 10, 1),
              ),
              ActivityTitle(
                network: 'wfc',
                sessions: 1,
                seconds: 300,
                last: DateTime.utc(2026, 10, 2),
              ),
            ],
          ),
        );
        expect(c.stats.first.value, '1 h 5 min');
        expect(c.rows.first.title, l.activityUnknown); // newest first
        expect(c.rows.first.value, '5 min');
        expect(c.rows.first.percent, 8);
        expect(c.rows.last.percent, 100);
        expect(c.rows.first.sub, contains('Wii / DS'));
      },
    );
  });

  group('screens', () {
    testWidgets('trophies: figures and rows, then empty and unlinked', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          TrophiesPage(
            api: _api({
              '/me/trophies': {
                'heading': 'psn_user',
                'linked': true,
                'stats': [
                  {'key': 'trophies.gold', 'value': '4', 'n': 4},
                ],
                'rows': [
                  {
                    'title': 'NPWR1',
                    'sub': '2026-10-01',
                    'value': '4',
                    'percent': -1,
                  },
                ],
              },
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gold'), findsOneWidget);
      expect(find.text('NPWR1'), findsOneWidget);
      expect(find.text('PSN online ID: psn_user'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          TrophiesPage(
            key: UniqueKey(),
            api: _api({
              '/me/trophies': {'linked': true, 'stats': [], 'rows': []},
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No trophies yet'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          TrophiesPage(
            key: UniqueKey(),
            api: _api({
              '/me/trophies': {'linked': false, 'stats': [], 'rows': []},
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No PlayStation 3 account'), findsOneWidget);
    });

    testWidgets('trophies: a failure is shown, not a blank', (tester) async {
      await tester.pumpWidget(
        _app(TrophiesPage(key: UniqueKey(), api: _api({}))),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('404'), findsOneWidget);
    });

    testWidgets('activity: rows, then empty', (tester) async {
      await tester.pumpWidget(
        _app(
          ActivityPage(
            api: _api({
              '/me/activity': {
                'titles': [
                  {
                    'network': 'switch',
                    'title': 'Outbound',
                    'sessions': 3,
                    'seconds': 5400,
                    'last_played': '2026-10-02T10:00:00Z',
                  },
                ],
                'total_seconds': 5400,
                'sessions': 3,
              },
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Outbound'), findsOneWidget);
      expect(find.text('1 h 30 min'), findsWidgets);
      expect(find.textContaining('3 sessions'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          ActivityPage(
            key: UniqueKey(),
            api: _api({
              '/me/activity': {'titles': [], 'total_seconds': 0, 'sessions': 0},
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No play recorded yet'), findsOneWidget);
    });

    testWidgets(
      'rankings hub lists games, opens a board with the own row marked',
      (tester) async {
        final api = _api({
          '/rankings': {
            'games': [
              {
                'slug': 'mkw',
                'name': 'Mario Kart Wii',
                'console': 'Wii',
                'boards': 2,
              },
            ],
          },
          '/companion/titles/mkw/rankings': _ranking,
        });
        await tester.pumpWidget(_app(RankingsPage(api: api)));
        await tester.pumpAndSettle();
        expect(find.text('Mario Kart Wii'), findsOneWidget);
        expect(find.text('2 boards'), findsOneWidget);
        await tester.tap(find.text('Mario Kart Wii'));
        await tester.pumpAndSettle();
        expect(find.text('Ann'), findsOneWidget);
        expect(find.text('1:02.000'), findsOneWidget);
        expect(find.text('Around you'), findsOneWidget);
        expect(find.text('Course B'), findsOneWidget); // board picker
        expect(find.text('Next'), findsOneWidget);
      },
    );

    testWidgets('rankings hub empty', (tester) async {
      await tester.pumpWidget(
        _app(
          RankingsPage(
            api: _api({
              '/rankings': {'games': []},
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No game has recorded rankings'),
        findsOneWidget,
      );
    });

    testWidgets('an empty board says so', (tester) async {
      final api = _api({
        '/companion/titles/x/rankings': {
          'boards': [],
          'board': 'a',
          'label': 'A',
          'entries': [],
          'offset': 0,
        },
      });
      await tester.pumpWidget(
        _app(
          RankingGamePage(
            api: api,
            game: RankedGame(slug: 'x', name: 'X'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing has been recorded'), findsOneWidget);
    });

    testWidgets('sites list the four sites with their open buttons', (
      tester,
    ) async {
      siteMarksFromNetwork = false;
      addTearDown(() => siteMarksFromNetwork = true);
      await tester.pumpWidget(_app(SitesPage(api: _api({}))));
      await tester.pumpAndSettle();
      expect(find.text('Open OpenSplat'), findsOneWidget);
      expect(find.text('Stage rotations and Splatfest.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Open OpenVerse'), 200);
      expect(find.text('Open OpenVerse'), findsOneWidget);
    });

    testWidgets(
      'game page: tabs only for what it has; an Open button on a mapped game',
      (tester) async {
        final api = _api({
          '/companion/titles/mkw': {
            'slug': 'mkw',
            'name': 'Mario Kart Wii',
            'console': 'Wii',
            'features': ['rankings', 'listings'],
          },
          '/companion/titles/mkw/rankings': _ranking,
          '/companion/titles/mkw/listings': {
            'stats': [],
            'rows': [],
            'linked': true,
          },
        });
        await tester.pumpWidget(
          _app(
            TitleDetailPage(
              api: api,
              item: CatalogItem(
                id: '1',
                kind: 'title',
                name: 'Mario Kart Wii',
                console: 'Wii',
                status: 'live',
              ),
              companion: CompanionTitle(
                slug: 'mkw',
                name: 'Mario Kart Wii',
                console: 'Wii',
                features: const ['rankings', 'listings'],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tab('Overview'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(TabBar),
            matching: find.text('Rankings'),
          ),
          findsOneWidget,
        );
        expect(tab('Trades'), findsOneWidget);
        expect(find.text('My stats'), findsNothing);
        expect(find.text('Open OpenKart'), findsOneWidget);
        await tester.tap(tab('Trades'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Nothing is listed'), findsOneWidget);
      },
    );

    testWidgets('game without companion pages shows no tabs', (tester) async {
      await tester.pumpWidget(
        _app(
          TitleDetailPage(
            api: _api({}),
            item: CatalogItem(
              id: '1',
              kind: 'title',
              name: 'Outbound',
              console: 'Switch',
              status: 'live',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsNothing);
      expect(find.textContaining('Nothing more is shown'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'companion_widgets.dart';
import 'l10n.dart';
import 'theme.dart';
import 'titles_page.dart' show consoleAsset;
import 'widgets.dart';

/// Games grouped by console, in the order of their first appearance; each game by name.
Map<String, List<RankedGame>> groupByConsole(
  List<RankedGame> games, [
  String search = '',
]) {
  final q = search.trim().toLowerCase();
  final out = <String, List<RankedGame>>{};
  final sorted = [...games]
    ..sort((a, b) {
      final c = a.console.compareTo(b.console);
      if (c != 0) return c;
      // Games with scores first, then by name.
      if (a.hasScores != b.hasScores) return a.hasScores ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  for (final g in sorted) {
    if (q.isNotEmpty && !g.name.toLowerCase().contains(q)) continue;
    (out[g.console] ??= []).add(g);
  }
  return out;
}

/// Leaderboards of every game that keeps scores, times or ratings (the website's
/// /rankings): pick a game, then its boards.
class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> {
  late Future<List<RankedGame>> _data = widget.api.rankedGames();
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = tokensOf(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.rankingsTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: () async => setState(() => _data = widget.api.rankedGames()),
        child: FutureBuilder<List<RankedGame>>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final pad = pagePadding(context, top: 12);
            if (snap.hasError) return LoadFailure(snap.error);
            final games = snap.data!;
            final groups = groupByConsole(games, _search);
            return ListView(
              padding: pad,
              children: [
                Text(
                  l.rankingsSub,
                  style: TextStyle(color: t.ink2, height: 1.4),
                ),
                const SizedBox(height: 14),
                if (games.isEmpty)
                  EmptyNote(l.rankingsEmpty)
                else ...[
                  TextField(
                    decoration: InputDecoration(
                      hintText: l.commonSearchByName,
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 8),
                  for (final e in groups.entries) ...[
                    SectionLabel(e.key),
                    Panel(
                      child: Column(
                        children: [
                          for (var i = 0; i < e.value.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              leading: SvgPicture.asset(
                                'assets/consoles/${consoleAsset(e.value[i].console, Theme.of(context).brightness)}.svg',
                                width: 42,
                                height: 28,
                                excludeFromSemantics: true,
                              ),
                              title: Text(
                                e.value[i].name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(_subtitle(l, e.value[i])),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RankingGamePage(
                                    api: widget.api,
                                    game: e.value[i],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "3 boards", or for a game nobody has scored in: "No scores yet — be the
/// first" and the names of its boards.
String _subtitle(AppLocalizations l, RankedGame g) {
  if (g.hasScores) return l.rankingsBoardsN(g.boards);
  final names = g.boardNames.take(4).join(', ');
  final more = g.boardNames.length - 4;
  return [
    l.rankingsNoScores,
    if (names.isNotEmpty) '$names${more > 0 ? ' ${l.rankingsMore(more)}' : ''}',
  ].join('\n');
}

/// One game's boards, opened from the hub.
class RankingGamePage extends StatelessWidget {
  const RankingGamePage({super.key, required this.api, required this.game});
  final OpenPakApi api;
  final RankedGame game;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: glassAppBar(title: Text(game.name)),
    body: RankingBoardView(api: api, slug: game.slug, topInset: true),
  );
}

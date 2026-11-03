import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// The words for a card figure. The server sends a stable key; one it has
/// not got a word for here shows the last part of it, capitalised.
String statLabel(AppLocalizations l, String key) => switch (key) {
  'trophies.total' => l.trophiesTotal,
  'trophies.points' => l.trophiesPoints,
  'trophies.platinum' => l.trophiesPlatinum,
  'trophies.gold' => l.trophiesGold,
  'trophies.silver' => l.trophiesSilver,
  'trophies.bronze' => l.trophiesBronze,
  'activity.total' => l.activityTotal,
  'activity.games' => l.activityGames,
  'activity.sessions' => l.activitySessions,
  'companion.listings.open' => l.companionListingsOpen,
  _ => () {
    final last = key.split('.').last;
    return last.isEmpty ? '' : last[0].toUpperCase() + last.substring(1);
  }(),
};

/// A card as the website draws it: the figures in a grid, then the list, each
/// line with its bar when it has a percentage.
class CardView extends StatelessWidget {
  const CardView({super.key, required this.card});
  final CompanionCard card;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (card.stats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final s in card.stats)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 104,
                      maxWidth: 200,
                    ),
                    child: Panel(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.value,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              statLabel(l, s.key),
                              style: TextStyle(color: t.muted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (card.rows.isNotEmpty)
          Panel(
            child: Column(
              children: [
                for (var i = 0; i < card.rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    card.rows[i].title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (card.rows[i].sub.isNotEmpty)
                                    Text(
                                      card.rows[i].sub,
                                      style: TextStyle(
                                        color: t.muted,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (card.rows[i].value.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              Text(
                                card.rows[i].value,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (card.rows[i].percent >= 0) ...[
                          const SizedBox(height: 8),
                          UsageBar(value: card.rows[i].percent / 100),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A line of muted text centred in a scrollable, so pull-to-refresh still works.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: tokensOf(context).muted, height: 1.4),
    ),
  );
}

/// A board of a game: the board picker, the rows, the signed-in player's own
/// slice and a pager. Used by the rankings hub and by a game's Rankings tab.
/// [topInset] is the space under a glass app bar when there is one.
class RankingBoardView extends StatefulWidget {
  const RankingBoardView({
    super.key,
    required this.api,
    required this.slug,
    this.topInset = false,
  });
  final OpenPakApi api;
  final String slug;
  final bool topInset;

  @override
  State<RankingBoardView> createState() => _RankingBoardViewState();
}

class _RankingBoardViewState extends State<RankingBoardView> {
  late Future<RankingPage> _data;
  String? _board;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _data = widget.api.companionRankings(
    widget.slug,
    board: _board,
    offset: _offset,
  );

  void _go({String? board, int? offset}) => setState(() {
    if (board != null) _board = board;
    _offset = offset ?? 0;
    _load();
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pad = widget.topInset
        ? pagePadding(context, top: 12)
        : const EdgeInsets.fromLTRB(20, 12, 20, 24);
    return RefreshIndicator(
      edgeOffset: widget.topInset ? glassTop(context) : 0,
      onRefresh: () async => setState(_load),
      child: FutureBuilder<RankingPage>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return LoadFailure(snap.error);
          }
          final r = snap.data!;
          final t = tokensOf(context);
          return ListView(
            padding: pad,
            children: [
              if (r.boards.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final b in r.boards)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              selected: b.id == r.board,
                              label: Text(b.label),
                              onSelected: (_) => _go(board: b.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (r.label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    r.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              if (r.entries.isEmpty)
                EmptyNote(l.companionRankingsEmpty)
              else
                Panel(
                  child: _Rows(rows: r.entries, api: widget.api),
                ),
              if (r.hasPrev || r.hasNext)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: r.hasPrev
                            ? () => _go(
                                offset: (r.offset - r.limit).clamp(0, r.total),
                              )
                            : null,
                        child: Text(l.companionRankingsPrev),
                      ),
                      Expanded(
                        child: Text(
                          l.companionRankingsShowing(
                            r.offset + 1,
                            r.offset + r.entries.length,
                            r.total,
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: t.muted, fontSize: 12.5),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: r.hasNext
                            ? () => _go(offset: r.offset + r.limit)
                            : null,
                        child: Text(l.companionRankingsNext),
                      ),
                    ],
                  ),
                ),
              if (r.around.isNotEmpty) ...[
                const SizedBox(height: 8),
                SectionLabel(l.companionRankingsAround),
                Panel(
                  child: _Rows(rows: r.around, api: widget.api),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.rows, required this.api});
  final List<RankEntry> rows;
  final OpenPakApi api;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          Container(
            color: rows[i].me ? t.accentWeak : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '${rows[i].rank}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: t.ink2,
                    ),
                  ),
                ),
                Avatar(
                  name: rows[i].name,
                  avatarUrl: rows[i].avatar == null
                      ? null
                      : api.absolute(rows[i].avatar!),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows[i].name,
                        style: TextStyle(
                          fontWeight: rows[i].me
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      if (rows[i].region.isNotEmpty || rows[i].note.isNotEmpty)
                        Text(
                          [
                            rows[i].region,
                            rows[i].note,
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: TextStyle(color: t.muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  rows[i].display,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

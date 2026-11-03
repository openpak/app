import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'open_url.dart';
import 'title_art.dart';
import 'companion_widgets.dart';
import 'l10n.dart';
import 'open_sites.dart';
import 'sites_page.dart';
import 'theme.dart';
import 'titles_page.dart' show consoleAsset, statusLabel, statusState;
import 'widgets.dart';

/// The companion record of a catalogue title, matched the way the website names
/// them: by name and console, case-insensitively. Null when it has none.
CompanionTitle? companionFor(List<CompanionTitle> all, CatalogItem item) {
  for (final c in all) {
    if (c.name.toLowerCase() == item.name.toLowerCase() &&
        c.console.toLowerCase() == item.console.toLowerCase()) {
      return c;
    }
  }
  return null;
}

/// The tabs a game page shows, in order: Overview first, then one per feature the
/// server lists (the only ones that have data). Unknown features are left out.
List<String> companionTabs(Iterable<String> features) {
  const known = {'rankings', 'stats', 'listings'};
  final out = <String>[];
  for (final f in features) {
    if (known.contains(f) && !out.contains(f)) out.add(f);
  }
  return out.isEmpty ? const [] : ['overview', ...out];
}

String _tabLabel(AppLocalizations l, String tab) => switch (tab) {
  'rankings' => l.companionTabRankings,
  'stats' => l.companionTabStats,
  'listings' => l.companionTabListings,
  _ => l.companionTabOverview,
};

/// A game: its status, the Open site that covers it and, when it has any, the
/// Overview / Rankings / Stats / Trades tabs of the website's game page.
class TitleDetailPage extends StatefulWidget {
  const TitleDetailPage({
    super.key,
    required this.api,
    required this.item,
    this.companion,
  });
  final OpenPakApi api;
  final CatalogItem item;
  final CompanionTitle? companion;

  @override
  State<TitleDetailPage> createState() => _TitleDetailPageState();
}

class _TitleDetailPageState extends State<TitleDetailPage> {
  Future<List<String>>? _features;

  @override
  void initState() {
    super.initState();
    final c = widget.companion;
    // The list the Titles screen fetched may be older than this visit; ask again,
    // and keep what it said if the answer does not come.
    if (c != null) {
      _features = widget.api
          .companionTitle(c.slug)
          .then((t) => t.features)
          .catchError((_) => c.features);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final site = siteFor(item.name, item.console);
    final (bg, line, ink) = stateColors(context, statusState(item.status));
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          SizedBox(width: 72, height: 72, child: TitleArt(api: widget.api, item: item)),
          const SizedBox(width: 14),
          if (item.console.isNotEmpty) ...[
            SvgPicture.asset(
              'assets/consoles/${consoleAsset(item.console, Theme.of(context).brightness)}.svg',
              width: 42,
              height: 28,
              semanticsLabel: item.console,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              item.console,
              style: TextStyle(color: tokensOf(context).muted),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: line),
            ),
            child: Text(
              statusLabel(context.l10n, item.status),
              style: TextStyle(
                color: ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    final feats = _features;
    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: feats == null
          ? Column(
              children: [
                header,
                Expanded(
                  child: _Overview(
                    api: widget.api,
                    site: site,
                    verseUrl: item.verseUrl,
                    features: const [],
                    onTab: (_) {},
                  ),
                ),
              ],
            )
          : FutureBuilder<List<String>>(
              future: feats,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _Tabs(
                  api: widget.api,
                  slug: widget.companion!.slug,
                  header: header,
                  site: site,
                  verseUrl: item.verseUrl,
                  features: snap.data!,
                );
              },
            ),
    );
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs({
    required this.api,
    required this.slug,
    required this.header,
    required this.site,
    required this.verseUrl,
    required this.features,
  });
  final OpenPakApi api;
  final String slug;
  final Widget header;
  final OpenSite? site;
  final String verseUrl;
  final List<String> features;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> with SingleTickerProviderStateMixin {
  late final List<String> _tabs = companionTabs(widget.features);
  late final TabController _ctl = TabController(
    length: _tabs.isEmpty ? 1 : _tabs.length,
    vsync: this,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Widget _body(String tab) => switch (tab) {
    'rankings' => RankingBoardView(api: widget.api, slug: widget.slug),
    'stats' => _CardTab(
      key: const ValueKey('stats'),
      load: widget.api.token == null
          ? null
          : () => widget.api.companionStats(widget.slug),
      kind: _CardKind.stats,
    ),
    'listings' => _CardTab(
      key: const ValueKey('listings'),
      load: () => widget.api.companionListings(widget.slug),
      kind: _CardKind.listings,
    ),
    _ => _Overview(
      api: widget.api,
      site: widget.site,
      verseUrl: widget.verseUrl,
      features: _tabs.skip(1).toList(),
      onTab: (f) => _ctl.animateTo(_tabs.indexOf(f)),
    ),
  };

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) {
      return Column(
        children: [
          widget.header,
          Expanded(
            child: _Overview(
              api: widget.api,
              site: widget.site,
              verseUrl: widget.verseUrl,
              features: const [],
              onTab: (_) {},
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        widget.header,
        TabBar(
          controller: _ctl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in _tabs) Tab(text: _tabLabel(context.l10n, t))],
        ),
        Expanded(
          child: TabBarView(
            controller: _ctl,
            children: [for (final t in _tabs) _body(t)],
          ),
        ),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.api,
    required this.site,
    required this.verseUrl,
    required this.features,
    required this.onTab,
  });
  final OpenPakApi api;
  final OpenSite? site;
  final String verseUrl;
  final List<String> features;
  final void Function(String) onTab;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = tokensOf(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (features.isNotEmpty) ...[
          Text(
            l.companionOverview,
            style: TextStyle(color: t.ink2, height: 1.4),
          ),
          const SizedBox(height: 8),
          SectionLabel(l.titlesDetailMore),
          Panel(
            child: Column(
              children: [
                for (var i = 0; i < features.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      _tabLabel(l, features[i]),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onTab(features[i]),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (site != null)
          FilledButton.icon(
            onPressed: () => openSite(site!),
            icon: const Icon(Icons.open_in_new),
            label: Text(l.sitesOpen(site!.name)),
          ),
        if (verseUrl.isNotEmpty) ...[
          if (site != null) const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => openExternalUrl(Uri.parse(verseUrl)),
            icon: const Icon(Icons.forum_outlined),
            label: Text(l.sitesVerseCommunity),
          ),
        ],
        if (features.isEmpty && site == null && verseUrl.isEmpty) EmptyNote(l.companionNone),
      ],
    );
  }
}

enum _CardKind { stats, listings }

class _CardTab extends StatefulWidget {
  const _CardTab({super.key, required this.load, required this.kind});

  /// Null when the tab needs a sign-in and there is none.
  final Future<CompanionCard> Function()? load;
  final _CardKind kind;

  @override
  State<_CardTab> createState() => _CardTabState();
}

class _CardTabState extends State<_CardTab> with AutomaticKeepAliveClientMixin {
  Future<CompanionCard>? _data;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _data = widget.load?.call();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l10n;
    final stats = widget.kind == _CardKind.stats;
    if (_data == null) {
      return ListView(children: [EmptyNote(l.companionStatsSignin)]);
    }
    return RefreshIndicator(
      onRefresh: () async => setState(() => _data = widget.load!()),
      child: FutureBuilder<CompanionCard>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          const pad = EdgeInsets.fromLTRB(20, 12, 20, 24);
          if (snap.hasError) {
            final e = snap.error;
            // The website words a backend that did not answer; a 404 means no data at all.
            if (e is ApiException && e.statusCode >= 500) {
              return ListView(
                padding: pad,
                children: [
                  EmptyNote(
                    stats
                        ? l.companionStatsUnavailable
                        : l.companionListingsUnavailable,
                  ),
                ],
              );
            }
            return LoadFailure(e);
          }
          final c = snap.data!;
          if (stats && !c.linked) {
            return ListView(
              padding: pad,
              children: [EmptyNote(l.companionStatsUnlinked)],
            );
          }
          if (c.rows.isEmpty && c.stats.isEmpty) {
            return ListView(
              padding: pad,
              children: [
                EmptyNote(
                  stats ? l.companionStatsEmpty : l.companionListingsEmpty,
                ),
              ],
            );
          }
          return ListView(
            padding: pad,
            children: [
              CardView(card: c),
              if (c.rows.isEmpty)
                EmptyNote(
                  stats ? l.companionStatsEmpty : l.companionListingsEmpty,
                ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// What works, what is asked for, and what to build next. Titles and network
/// features come from the same catalog as the website's /titles and /features
/// pages. A title that is not started yet (requestable/planned) carries a
/// Request button — the prioritisation signal — while a started title (live,
/// beta, alpha) just shows its status pill. The ranking those requests produce
/// is internal; it is not shown here. The Network view is a read-only status
/// matrix. Reachable signed out; the Request control only acts with a bearer.
class TitlesPage extends StatefulWidget {
  const TitlesPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<TitlesPage> createState() => TitlesPageState();
}

class TitlesPageState extends State<TitlesPage> {
  late Future<List<CatalogItem>> _data;
  late Future<NetworkStatus> _online;
  late Future<List<NewsArticle>> _news;

  // View controls, all applied client-side over the one fetched list — the
  // same as the web page, and it keeps a filter change from hitting the server.
  String _kind = 'title'; // 'title' | 'feature'
  String _search = '';
  String? _console; // null = all
  String? _status; // null = all

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() {
    _data = widget.api.requests();
    _online = widget.api.status();
    _news = widget.api.news();
  });

  /// A request is optimistic: flip the row before the call, then let the
  /// server's authoritative state settle it. The count is internal, so it is
  /// not shown — only the requested/not-requested state is.
  Future<void> _request(CatalogItem item) async {
    if (widget.api.token == null) return; // signed out — no toggle
    final items = await _data;
    void set(CatalogItem next) => setState(() {
      _data = Future.value([
        for (final i in items) i.id == next.id ? next : i,
      ]);
    });
    set(item.withVote(votes: item.votes + (item.voted ? -1 : 1), voted: !item.voted));
    try {
      final r = await widget.api.vote(item.id);
      set(item.withVote(votes: r.votes, voted: r.voted));
    } on ApiException catch (e) {
      // 409 = the id is not requestable (a started game or a feature). The
      // button is gated so this should be unreachable; restore the true state.
      if (e.statusCode != 409 && mounted) showToast(context, apiErrorText(context.l10n, e));
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.api.token != null;
    final isTitle = _kind == 'title';
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.titlesTitle)),
      body: RefreshIndicator(
        onRefresh: () async => reload(),
        child: FutureBuilder<List<CatalogItem>>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final all = snap.data ?? const <CatalogItem>[];
            // The list is what has a server; the long tail sits behind "Request a game".
            final served = all.where((i) => !(i.kind == 'title' && notStarted(i.status))).toList();
            final requestable = all.where((i) => i.kind == 'title' && notStarted(i.status)).toList()..sort(catalogOrder);
            final shown = filterCatalog(served, kind: _kind, search: _search, console: _console, status: _status);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _latestNews(),
                _onlineNow(),
                _segmented(),
                const SizedBox(height: 12),
                _controls(served),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Text(l.titlesNothingMatches, textAlign: TextAlign.center, style: TextStyle(color: tokensOf(context).muted)),
                  )
                else
                  ...shown.map((i) => _CatalogRow(
                        item: i,
                        showRequest: false,
                        signedIn: signedIn,
                        onRequest: () {},
                      )),
                if (isTitle && requestable.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _openRequestSheet(requestable, signedIn),
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(l.titlesRequestGame),
                  ),
                  const SizedBox(height: 6),
                  Text(l.titlesRequestHint, style: TextStyle(fontSize: 12, color: tokensOf(context).muted)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// "Request a game": a sheet with one dropdown of the titles that have no server yet,
  /// grouped by console in the label, and a button that toggles this account's request.
  Future<void> _openRequestSheet(List<CatalogItem> requestable, bool signedIn) async {
    CatalogItem? picked = requestable.first;
    final l = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.titlesRequestSheetTitle, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<CatalogItem>(
                initialValue: picked,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.titlesPickTitle),
                items: [
                  for (final i in requestable)
                    DropdownMenuItem(
                      value: i,
                      child: Text('${i.console} · ${i.name}${i.voted ? '  ${l.titlesRequestedMark}' : ''}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setSheet(() => picked = v),
              ),
              const SizedBox(height: 16),
              if (!signedIn)
                Text(l.titlesSignInToRequest, style: TextStyle(color: tokensOf(context).muted))
              else
                FilledButton(
                  onPressed: picked == null
                      ? null
                      : () async {
                          final item = picked!;
                          Navigator.of(ctx).pop();
                          await _request(item);
                        },
                  child: Text(picked?.voted == true ? l.titlesWithdraw : l.titlesRequest),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The website's news, newest first, as its landing page shows them. Nothing
  /// at all when there are none or they cannot be read; the catalog still is.
  Widget _latestNews() => FutureBuilder<List<NewsArticle>>(
        future: _news,
        builder: (context, snap) {
          final articles = snap.data ?? const <NewsArticle>[];
          if (articles.isEmpty) return const SizedBox.shrink();
          final t = tokensOf(context);
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(context.l10n.titlesNews),
                for (final a in articles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      child: InkWell(
                        onTap: () => _openArticle(a),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (a.publishedAt != null) ...[
                                const SizedBox(height: 2),
                                Text(newsDate(context.l10n, a.publishedAt!), style: TextStyle(color: t.muted, fontSize: 12.5)),
                              ],
                              if (a.summary.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(a.summary,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: t.ink2, fontSize: 13.5, height: 1.4)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  /// The whole article, in a sheet over the tab it was opened from.
  Future<void> _openArticle(NewsArticle a) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (ctx, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Text(a.title, style: Theme.of(ctx).textTheme.titleLarge),
              if (a.publishedAt != null) ...[
                const SizedBox(height: 4),
                Text(newsDate(ctx.l10n, a.publishedAt!), style: TextStyle(color: tokensOf(ctx).muted)),
              ],
              const SizedBox(height: 16),
              for (final para in (a.body.isEmpty ? a.summary : a.body).split(RegExp(r'\n\s*\n')))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(para.trim(), style: const TextStyle(height: 1.5)),
                ),
            ],
          ),
        ),
      );

  /// The website's status page in brief: who is online, per console network.
  /// Nothing is shown when the counts cannot be read; the catalog still is.
  Widget _onlineNow() => FutureBuilder<NetworkStatus>(
        future: _online,
        builder: (context, snap) {
          final s = snap.data;
          if (s == null) return const SizedBox.shrink();
          final online = context.l10n.titlesOnlineCount;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(context.l10n.titlesOnlineNow, trailing: online(s.playersOnline)),
                for (final e in s.networks.entries)
                  StateRow(
                    name: platformNames[e.key] ?? e.key,
                    pill: online(e.value),
                    state: e.value > 0 ? RowState.ok : RowState.idle,
                  ),
              ],
            ),
          );
        },
      );

  Widget _segmented() => SegmentedButton<String>(
    segments: [
      ButtonSegment(value: 'title', label: Text(context.l10n.titlesTitle), icon: const Icon(Icons.sports_esports_outlined)),
      ButtonSegment(value: 'feature', label: Text(context.l10n.titlesNetwork), icon: const Icon(Icons.lan_outlined)),
    ],
    selected: {_kind},
    showSelectedIcon: false,
    onSelectionChanged: (s) => setState(() {
      _kind = s.first;
      // Filters that made sense for one kind rarely do for the other.
      _console = null;
      _status = null;
    }),
  );

  /// Search, then the two dropdowns. Console is only meaningful for titles
  /// (features have none), so it is dropped on the Network view.
  Widget _controls(List<CatalogItem> all) {
    final ofKind = all.where((i) => i.kind == _kind);
    final consoles = _distinct(ofKind.map((i) => i.console));
    final statuses = _distinct(ofKind.map((i) => i.status));
    final l = context.l10n;
    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: l.commonSearchByName,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 10),
        _chips(
          selected: _status,
          all: l.titlesAllStatuses,
          options: statuses,
          label: (s) => statusLabel(l, s),
          onSelected: (v) => setState(() => _status = v),
        ),
        if (_kind == 'title') ...[
          const SizedBox(height: 8),
          _chips(
            selected: _console,
            all: l.commonAllConsoles,
            options: consoles,
            label: (c) => c,
            logo: true,
            onSelected: (v) => setState(() => _console = v),
          ),
        ],
      ],
    );
  }

  /// The site's filter chips: one scrolling row, "all" first, the chosen one
  /// inverted (ink on paper) so it reads as selected without a colour.
  Widget _chips({
    required String? selected,
    required String all,
    required List<String> options,
    required String Function(String) label,
    required ValueChanged<String?> onSelected,
    bool logo = false,
  }) {
    final theme = Theme.of(context);
    Widget chip(String? value, String text) {
      final on = selected == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: on,
          onSelected: (_) => onSelected(value),
          label: Text(text),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: on ? theme.scaffoldBackgroundColor : theme.colorScheme.onSurface,
          ),
          avatar: logo && value != null
              ? SvgPicture.asset(
                  'assets/consoles/${consoleAsset(value, theme.brightness)}.svg',
                  width: 18,
                  height: 18,
                )
              : null,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [chip(null, all), for (final o in options) chip(o, label(o))]),
    );
  }

  static List<String> _distinct(Iterable<String> xs) {
    final seen = xs.where((x) => x.isNotEmpty).toSet().toList()..sort();
    return seen;
  }
}

/// One catalog entry — titles and network features alike — as a single line:
/// the console logo, the name (which fills the row so the trailing control is
/// always right-aligned), and on the right either a Request button (a
/// not-started title) or a status pill. Only the pill carries colour; the row
/// is neutral, matching the website.
class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.item,
    required this.showRequest,
    required this.signedIn,
    required this.onRequest,
  });
  final CatalogItem item;
  final bool showRequest;
  final bool signedIn;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = statusState(item.status);
    final (pillBg, pillLine, pillInk) = switch (state) {
      RowState.ok => (t.okWeak, t.okLine, t.ok),
      RowState.beta => (t.accentWeak, t.accentLine, Theme.of(context).colorScheme.primary),
      RowState.warn => (t.warnWeak, t.warnLine, t.warn),
      RowState.bad => (t.badWeak, t.badLine, t.bad),
      RowState.idle => (t.paper2, t.line, t.ink2),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: t.line),
        boxShadow: t.shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (item.console.isNotEmpty) ...[
              // No colorFilter: each mark carries its console's own colour, the
              // same file the website serves. The slot is 3:2 because the Wii,
              // Wii U and PlayStation marks are wordmarks -- a square box would
              // shrink them to an illegible smear; square device marks letterbox
              // inside it.
              SvgPicture.asset(
                'assets/consoles/${consoleAsset(item.console, Theme.of(context).brightness)}.svg',
                width: 33,
                height: 22,
                semanticsLabel: item.console,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (showRequest)
              _RequestButton(requested: item.voted, enabled: signedIn, onTap: onRequest)
            else
              _StatusPill(label: statusLabel(context.l10n, item.status), color: pillInk, border: pillLine, bg: pillBg),
          ],
        ),
      ),
    );
  }
}

/// The Request control: a small pill button. Filled when already requested, an
/// outline when not, muted-static when signed out. No count — the ranking is
/// internal.
class _RequestButton extends StatelessWidget {
  const _RequestButton({required this.requested, required this.enabled, required this.onTap});
  final bool requested;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final scheme = Theme.of(context).colorScheme;
    final active = enabled && requested;
    final color = !enabled ? t.muted : (requested ? scheme.primary : t.ink2);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? t.accentWeak : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? scheme.primary : t.line2),
        ),
        child: Text(
          requested ? context.l10n.titlesRequested : context.l10n.titlesRequest,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color, required this.border, required this.bg});
  final String label;
  final Color color;
  final Color border;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
    ),
  );
}

// ── Pure helpers, unit-tested ────────────────────────────────────────────────

/// Whether a title has not been started yet: requestable or planned. These are
/// the only ones that carry a Request button; alpha/beta/live are started, so
/// they show a status pill. Callers gate this behind kind == title.
bool notStarted(String status) => status == 'requestable' || status == 'planned';

/// The asset basename of a console's mark under assets/consoles. Unknown
/// consoles fall back to a generic gamepad glyph. Keep in step with the
/// website's consoleSlug and with the assets actually bundled; the assets are
/// byte-for-byte copies of website/web/static/consoles.
///
/// Every mark ships twice. Most keep their real brand colours, and a few of
/// those -- the PlayStation family's navy, the DS logo's black -- are unreadable
/// on a dark row, so `-dark` carries a lightened copy. Marks with no colour
/// version anywhere are tinted and their two files are identical.
String consoleAsset(String console, [Brightness brightness = Brightness.light]) =>
    _consoleBase(console) + (brightness == Brightness.dark ? '-dark' : '');

String _consoleBase(String console) => switch (console) {
  'Switch' => 'switch',
  'Wii' => 'wii',
  'Wii U' => 'wii-u',
  'DS' => 'ds',
  '3DS' => '3ds',
  'Xbox' => 'xbox',
  'Xbox 360' => 'xbox-360',
  'PS2' => 'ps2',
  'PS3' => 'ps3',
  'PSP' => 'psp',
  'Vita' => 'vita',
  _ => 'generic',
};

/// Filter to one kind, by console/status/name, in catalogOrder. Optionally re-sort by
/// votes for the internal scoreboard (not surfaced in the UI).
List<CatalogItem> filterCatalog(
  List<CatalogItem> items, {
  required String kind,
  String search = '',
  String? console,
  String? status,
  bool byVotes = false,
}) {
  final q = search.trim().toLowerCase();
  final out = items.where((i) {
    if (i.kind != kind) return false;
    if (console != null && i.console != console) return false;
    if (status != null && i.status != status) return false;
    if (q.isNotEmpty && !i.name.toLowerCase().contains(q)) return false;
    return true;
  }).toList();
  if (byVotes) {
    out.sort((a, b) => b.votes != a.votes ? b.votes.compareTo(a.votes) : a.name.compareTo(b.name));
  } else {
    out.sort(catalogOrder);
  }
  return out;
}

/// What can be played first, by console, alphabetically; then the long tail the same way.
/// The keys are chosen so a console filter leaves status-then-name order and a status filter
/// leaves console-then-name order, the same rule the website applies.
int statusRank(String status) => switch (status) {
  'live' || 'working' => 0,
  'beta' => 1,
  'alpha' || 'partial' => 2,
  'scaffold' => 3,
  'requestable' || 'planned' => 4,
  _ => 5,
};

int catalogOrder(CatalogItem a, CatalogItem b) {
  final pa = statusRank(a.status) <= 3, pb = statusRank(b.status) <= 3;
  if (pa != pb) return pa ? -1 : 1;
  final c = a.console.compareTo(b.console);
  if (c != 0) return c;
  final s = statusRank(a.status).compareTo(statusRank(b.status));
  if (s != 0) return s;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// How a status reads as a row tint. Working/live is the only "done"; the
/// broken/infeasible end is the only red; everything mid-flight is amber; the
/// not-yet-started (planned/requestable) makes no claim, so grey.
RowState statusState(String status) => switch (status) {
  'live' || 'working' || 'active' => RowState.ok,
  'beta' => RowState.beta,
  'alpha' || 'partial' || 'scaffold' || 'open' => RowState.warn,
  'not-feasible' || 'broken' || 'banned' => RowState.bad,
  _ => RowState.idle, // planned, requestable, anything new
};

/// A status token shown to a person: 'not-feasible' → 'Not feasible'. Unknown
/// values pass through capitalised rather than being dropped.
String statusLabel(AppLocalizations l, String status) => switch (status) {
  'live' => l.statusLive,
  'working' => l.statusWorking,
  'beta' => l.statusBeta,
  'scaffold' => l.statusScaffold,
  'alpha' => l.statusAlpha,
  'partial' => l.statusPartial,
  'planned' => l.statusPlanned,
  'requestable' => l.statusRequestable,
  'not-feasible' => l.statusNotFeasible,
  'broken' => l.statusBroken,
  '' => '—',
  _ => status[0].toUpperCase() + status.substring(1),
};

/// "18 September 2026", the website's news date, in UTC as it prints it. The
/// order and punctuation are the language's ("18. September 2026"), the month
/// name the locale's own.
String newsDate(AppLocalizations l, DateTime d) {
  final u = d.toUtc();
  return l.titlesNewsDate(u.day, DateFormat.MMMM(l.localeName).format(u), u.year);
}

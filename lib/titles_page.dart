import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// What works, what is asked for, and what to build next. Titles and network
/// features come from the same votable catalog as the website's /titles and
/// /features pages; voting is the prioritisation signal. Reachable signed out
/// (the counts are public); the vote button only acts when there is a bearer.
class TitlesPage extends StatefulWidget {
  const TitlesPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<TitlesPage> createState() => TitlesPageState();
}

class TitlesPageState extends State<TitlesPage> {
  late Future<List<CatalogItem>> _data;

  // View controls, all applied client-side over the one fetched list — the
  // same as the web page, and it keeps a filter change from hitting the server.
  String _kind = 'title'; // 'title' | 'feature'
  String _search = '';
  String? _console; // null = all
  String? _status; // null = all
  bool _byVotes = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() {
    _data = widget.api.requests();
  });

  /// Vote is optimistic: flip the row and adjust the count before the request,
  /// then correct from the server's authoritative numbers. A failure reloads,
  /// which puts the true state back.
  Future<void> _vote(CatalogItem item) async {
    if (widget.api.token == null) return; // signed out — no toggle
    final items = await _data;
    void set(CatalogItem next) => setState(() {
      _data = Future.value([
        for (final i in items) i.id == next.id ? next : i,
      ]);
    });
    set(item.withVote(
      votes: item.votes + (item.voted ? -1 : 1),
      voted: !item.voted,
    ));
    try {
      // The server returns only the new voted flag; the count is ours to
      // derive from the change, and reconciles on the next reload.
      final voted = await widget.api.vote(item.id);
      final delta = voted == item.voted ? 0 : (voted ? 1 : -1);
      set(item.withVote(votes: item.votes + delta, voted: voted));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.api.token != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Titles'),
        actions: [
          IconButton(
            tooltip: _byVotes ? 'Catalog order' : 'Most requested',
            icon: Icon(_byVotes ? Icons.sort : Icons.trending_up),
            onPressed: () => setState(() => _byVotes = !_byVotes),
          ),
        ],
      ),
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
            final shown = filterCatalog(
              all,
              kind: _kind,
              search: _search,
              console: _console,
              status: _status,
              byVotes: _byVotes,
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _segmented(),
                const SizedBox(height: 12),
                _controls(all),
                const SizedBox(height: 8),
                if (!signedIn) _signInHint(),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: ScrollableMessage('Nothing matches.'),
                  )
                else
                  ...shown.map((i) => _CatalogRow(
                        item: i,
                        signedIn: signedIn,
                        onVote: () => _vote(i),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _segmented() => SegmentedButton<String>(
    segments: const [
      ButtonSegment(value: 'title', label: Text('Titles'), icon: Icon(Icons.sports_esports_outlined)),
      ButtonSegment(value: 'feature', label: Text('Network'), icon: Icon(Icons.lan_outlined)),
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
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search by name',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_kind == 'title') ...[
              Expanded(
                child: _filterDropdown(
                  hint: 'Console',
                  value: _console,
                  options: consoles,
                  onChanged: (v) => setState(() => _console = v),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _filterDropdown(
                hint: 'Status',
                value: _status,
                options: statuses,
                onChanged: (v) => setState(() => _status = v),
                label: statusLabel,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _filterDropdown({
    required String hint,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String Function(String)? label,
  }) => DropdownButtonFormField<String?>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(hintText: hint, isDense: true),
    items: [
      DropdownMenuItem(value: null, child: Text('All ${hint.toLowerCase()}s')),
      ...options.map((o) => DropdownMenuItem(
            value: o,
            child: Text(label?.call(o) ?? o, overflow: TextOverflow.ellipsis),
          )),
    ],
    onChanged: onChanged,
  );

  Widget _signInHint() => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      'Sign in to vote. Counts are shown to everyone.',
      style: TextStyle(color: tokensOf(context).muted, fontSize: 13),
    ),
  );

  static List<String> _distinct(Iterable<String> xs) {
    final seen = xs.where((x) => x.isNotEmpty).toSet().toList()..sort();
    return seen;
  }
}

/// One title or feature: name, its status pill, the console/backend beneath,
/// and a vote button that reads as pressed once you have voted.
class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.item, required this.signedIn, required this.onVote});
  final CatalogItem item;
  final bool signedIn;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = statusState(item.status);
    final (bg, border, ink) = switch (state) {
      RowState.ok => (t.okWeak, t.okLine, t.ok),
      RowState.warn => (t.warnWeak, t.warnLine, t.warn),
      RowState.bad => (t.badWeak, t.badLine, t.bad),
      RowState.idle => (t.raised, t.line, t.muted),
    };
    final sub = [item.console, item.backend].where((s) => s.isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusPill(label: statusLabel(item.status), color: ink, border: border),
                    ],
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(sub, style: TextStyle(color: t.muted, fontSize: 12.5)),
                  ],
                  if (item.notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.notes, style: TextStyle(color: t.ink2, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _VoteButton(votes: item.votes, voted: item.voted, enabled: signedIn, onTap: onVote),
          ],
        ),
      ),
    );
  }
}

/// The vote control: an upvote arrow over the count. Filled when you have
/// voted, an outline when you have not, and muted-static when signed out — a
/// count you can read but not change.
class _VoteButton extends StatelessWidget {
  const _VoteButton({required this.votes, required this.voted, required this.enabled, required this.onTap});
  final int votes;
  final bool voted;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final scheme = Theme.of(context).colorScheme;
    final active = enabled && voted;
    final color = !enabled ? t.muted : (voted ? scheme.primary : t.ink2);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: active ? t.accentWeak : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? scheme.primary : t.line2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(voted ? Icons.arrow_drop_up : Icons.arrow_drop_up_outlined, color: color, size: 22),
            Text('$votes', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color, required this.border});
  final String label;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
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

/// Filter to one kind, by console/status/name, then optionally re-sort by
/// votes (the scoreboard). The server already returns catalog order, so the
/// default keeps it; byVotes ties break by name for a stable order.
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
  }
  return out;
}

/// How a status reads as a row tint. Working/live is the only "done"; the
/// broken/infeasible end is the only red; everything mid-flight is amber; the
/// not-yet-started (planned/requestable) makes no claim, so grey.
RowState statusState(String status) => switch (status) {
  'live' || 'working' => RowState.ok,
  'beta' || 'alpha' || 'partial' => RowState.warn,
  'not-feasible' || 'broken' => RowState.bad,
  _ => RowState.idle, // planned, requestable, anything new
};

/// A status token shown to a person: 'not-feasible' → 'Not feasible'. Unknown
/// values pass through capitalised rather than being dropped.
String statusLabel(String status) => switch (status) {
  'live' => 'Live',
  'working' => 'Working',
  'beta' => 'Beta',
  'alpha' => 'Alpha',
  'partial' => 'Partial',
  'planned' => 'Planned',
  'requestable' => 'Requestable',
  'not-feasible' => 'Not feasible',
  'broken' => 'Broken',
  '' => '—',
  _ => status[0].toUpperCase() + status.substring(1),
};

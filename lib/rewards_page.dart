import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'rewards_buy.dart';
import 'rewards_cards.dart';
import 'rewards_theme.dart';
import 'theme.dart';
import 'widgets.dart';

/// Rewards: the website's /account/rewards as four tabs under one header
/// (balance, today's cap, the next thing to do).
class RewardsPage extends StatefulWidget {
  const RewardsPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<RewardsPage> createState() => _RewardsPageState();
}

enum _Tab { missions, shop, collection, settings }

class _RewardsPageState extends State<RewardsPage> {
  RewardsView? _view;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  _Tab _tab = _Tab.missions;
  String _kind = '';
  ({String text, bool bad})? _msg;
  bool _showcase = false, _paused = false;

  OpenPakApi get api => widget.api;
  bool get _frozen => _view?.frozen ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads the screens. A refresh that fails keeps what is already shown.
  Future<void> _load() async {
    try {
      final v = await api.rewards();
      if (!mounted) return;
      setState(() {
        _view = v;
        _error = null;
        _loading = false;
        _showcase = v.showcasePublic;
        _paused = v.paused;
        if (_kind.isNotEmpty && !v.shop.any((g) => g.kind == _kind)) _kind = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_view == null) _error = e;
      });
    }
  }

  /// Runs one write: disables the buttons meanwhile, shows its outcome as a
  /// message, then re-reads the screens.
  Future<void> _act(Future<String> Function(AppLocalizations l) run) async {
    final l = context.l10n;
    setState(() {
      _busy = true;
      _msg = null;
    });
    String? ok, bad;
    try {
      ok = await run(l);
    } on ApiException catch (e) {
      bad = apiErrorText(l, e);
    } catch (e) {
      bad = LoadFailure.reasonOf(l, e);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = ok != null ? (text: ok, bad: false) : (text: bad ?? '', bad: true);
    });
    await _load();
  }

  Future<void> _claim(RewardsTile t) => _act((l) async {
    final pts = await api.claimReward(t.missionId, t.period);
    return l.rewardsMsgClaimedPts(pts);
  });

  Future<void> _equip(String slot, String item, String name, {bool clear = false}) {
    final c = RewardsThemeScope.maybeOf(context);
    return _act((l) async {
      await api.equipReward(slot, clear ? '' : item);
      if (slot == 'theme') {
        c?.stopPreview();
        unawaited(c?.load());
      }
      return clear ? l.rewardsMsgUnequipped : l.rewardsMsgEquipped(name);
    });
  }

  Future<void> _preview(RewardsItem item) async {
    final c = RewardsThemeScope.maybeOf(context);
    if (c == null) return;
    final l = context.l10n;
    if (!await c.startPreview(item) && mounted) showToast(context, l.rewardsPreviewFailed);
  }

  Future<void> _buy(RewardsItem item) async {
    final v = _view;
    if (v == null) return;
    final c = RewardsThemeScope.maybeOf(context);
    final l = context.l10n;
    final r = await showBuyDialog(context, api: api, item: item, balance: v.balance, frozen: v.frozen);
    if (!mounted) return;
    if (r == BuyResult.preview) return _preview(item);
    if (r == BuyResult.bought) {
      c?.stopPreview();
      setState(() => _msg = (text: l.rewardsMsgRedeemed(item.name), bad: false));
      await _load();
    }
  }

  Future<void> _saveSettings() => _act((l) async {
    await api.saveRewardsSettings(showcase: _showcase, paused: _paused);
    return l.rewardsMsgSaved;
  });

  void _go(_Tab tab) => setState(() => _tab = tab);

  String _tabLabel(AppLocalizations l, _Tab t) => switch (t) {
    _Tab.missions => l.rewardsTabMissions,
    _Tab.shop => l.rewardsTabShop,
    _Tab.collection => l.rewardsTabCollection,
    _Tab.settings => l.rewardsTabSettings,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final v = _view;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.rewardsTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: _load,
        // A Builder: below the Scaffold, whose MediaQuery counts the glass
        // bar in the top padding; this page's own context sees the status bar only.
        child: Builder(
          builder: (context) => _loading && v == null
              ? const Center(child: CircularProgressIndicator())
              : v == null
              ? _failure(context, l)
              : _body(context, l, v),
        ),
      ),
    );
  }

  Widget _failure(BuildContext context, AppLocalizations l) {
    final e = _error;
    final off = e is ApiException && (e.code == 'rewards_unavailable' || e.statusCode == 503);
    if (!off) return LoadFailure(e);
    final t = tokensOf(context);
    return ListView(
      padding: pagePadding(context, top: 24),
      children: [
        Text(l.rewardsUnavailable, textAlign: TextAlign.center, style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 8),
        Text(l.rewardsUnavailableHint, textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            child: Text(l.rewardsRetry),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, RewardsView v) {
    final t = tokensOf(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pagePadding(context, top: 16, bottom: 32),
      children: [
        if (_msg != null) ...[_message(_msg!), const SizedBox(height: 12)],
        _header(l, v),
        if (v.frozen) ...[const SizedBox(height: 12), _note(l.rewardsFrozen, bad: true)],
        if (v.paused) ...[
          const SizedBox(height: 12),
          _note(l.rewardsPaused, action: l.rewardsPausedGo, onAction: () => _go(_Tab.settings)),
        ],
        if (v.nextKind == 'claim' || (v.nextKind == 'buy' && _tab != _Tab.shop)) ...[
          const SizedBox(height: 12),
          _next(l, v),
        ] else if (v.nextKind == 'play' && v.nextText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(v.nextText, style: TextStyle(color: t.muted, fontSize: 13.5)),
        ],
        const SizedBox(height: 16),
        // One row that scrolls sideways, like the website's chips.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none, // chips run to the screen edge, not to the page padding
          child: Row(
            children: [
              for (final tab in _Tab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: RewardsChoice(
                    label: _tabLabel(l, tab),
                    selected: tab == _tab,
                    count: tab == _Tab.missions ? v.ready : null,
                    onTap: () => _go(tab),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...switch (_tab) {
          _Tab.missions => _missions(l, v),
          _Tab.shop => _shop(l, v),
          _Tab.collection => _collection(l, v),
          _Tab.settings => _settings(l, v),
        },
      ],
    );
  }

  Widget _message(({String text, bool bad}) m) {
    final t = tokensOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.bad ? t.badWeak : t.okWeak,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: m.bad ? t.badLine : t.okLine),
      ),
      child: Semantics(liveRegion: true, child: Text(m.text, style: const TextStyle(fontSize: 13.5, height: 1.4))),
    );
  }

  Widget _note(String text, {bool bad = false, String? action, VoidCallback? onAction}) {
    final t = tokensOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bad ? t.badWeak : t.warnWeak,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: bad ? t.badLine : t.warnLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }

  /// Balance with the equipped badge, today's play points against the cap,
  /// and the two small facts.
  Widget _header(AppLocalizations l, RewardsView v) {
    final t = tokensOf(context);
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RewardsImage(api: api, path: v.badge?.img ?? '', width: 64, circle: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${v.balance}', style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800, fontSize: 34, height: 1.1)),
                      Text(l.rewardsBalance, style: TextStyle(color: t.muted)),
                    ],
                  ),
                ),
              ],
            ),
            if (v.todayCap > 0) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text(l.rewardsToday, style: TextStyle(color: t.ink2))),
                  Text(l.rewardsTodayOf(v.todayPoints, v.todayCap), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              ProgressBar(percent: v.todayPercent),
              if (v.capReached || (!v.paused && v.more > 0))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    v.capReached ? l.rewardsTodayCap : l.rewardsTodayMore(v.more),
                    style: TextStyle(color: t.muted, fontSize: 12.5),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _mini('${v.owned}', l.rewardsOwnedCount, () => _go(_Tab.collection))),
                const SizedBox(width: 10),
                Expanded(child: _mini(v.playTime, l.rewardsPlaytime, null)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(String value, String label, VoidCallback? onTap) {
    final t = tokensOf(context);
    return Material(
      color: t.paper2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard), side: BorderSide(color: t.line)),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Scaled down, not wrapped: a duration such as "42 Std. 15 Min." stays one line.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, maxLines: 1, style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              Text(label, style: TextStyle(color: t.muted, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }

  /// The single suggestion: claim what is ready, or spend what is saved.
  Widget _next(AppLocalizations l, RewardsView v) {
    final t = tokensOf(context);
    final claim = v.nextKind == 'claim';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: claim ? t.okWeak : t.accentWeak,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: claim ? t.okLine : t.accentLine),
      ),
      child: Row(
        children: [
          Expanded(child: Text(v.nextText, style: const TextStyle(fontSize: 13.5, height: 1.4))),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => _go(claim ? _Tab.missions : _Tab.shop),
            child: Text(claim ? l.rewardsNextClaimGo : l.rewardsNextBuyGo),
          ),
        ],
      ),
    );
  }

  Widget _head(String text, {int? count}) => SectionLabel(text, trailing: count == null ? null : '$count');

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: TextStyle(color: tokensOf(context).muted)),
  );

  Widget _tileCard(RewardsTile t, TileMode mode) => MissionCard(
    api: api,
    tile: t,
    mode: mode,
    frozen: _frozen,
    busy: _busy,
    onOpen: () => _openLadder(t, mode),
    onClaim: () => _claim(t),
    onEquip: () => _equip('badge', t.equipItem, t.label.isEmpty ? t.name : t.label, clear: t.equipped),
  );

  List<Widget> _tileList(List<RewardsTile> tiles, TileMode mode) => [
    for (final t in tiles) Padding(padding: const EdgeInsets.only(bottom: 10), child: _tileCard(t, mode)),
  ];

  List<Widget> _missions(AppLocalizations l, RewardsView v) {
    final none = v.readyTiles.isEmpty && v.tiles.isEmpty && v.done.isEmpty;
    return [
      if (none) _empty(l.rewardsMEmpty),
      if (v.readyTiles.isNotEmpty) ...[_head(l.rewardsMReady, count: v.readyTiles.length), ..._tileList(v.readyTiles, TileMode.work), const SizedBox(height: 10)]
      else if (v.tiles.isNotEmpty) _empty(l.rewardsMNone),
      if (v.tiles.isNotEmpty) ...[_head(l.rewardsMProgress, count: v.tiles.length), ..._tileList(v.tiles, TileMode.work), const SizedBox(height: 10)],
      if (v.done.isNotEmpty) ...[_head(l.rewardsMDone, count: v.done.length), ..._tileList(v.done, TileMode.done), const SizedBox(height: 10)],
      _head(l.rewardsLedger),
      if (v.ledger.isEmpty) _empty(l.rewardsLedgerEmpty),
      for (final e in v.ledger) Padding(padding: const EdgeInsets.only(bottom: 8), child: EntryCard(api: api, entry: e)),
    ];
  }

  List<Widget> _shop(AppLocalizations l, RewardsView v) {
    final t = tokensOf(context);
    final groups = [for (final g in v.shop) if (_kind.isEmpty || g.kind == _kind) g];
    final hasItems = v.shop.any((g) => g.items.isNotEmpty);
    return [
      Text(l.rewardsShopSub, style: TextStyle(color: t.muted)),
      const SizedBox(height: 12),
      if (v.shop.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
            label: l.rewardsFilter,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                RewardsChoice(label: l.rewardsFilterAll, selected: _kind.isEmpty, onTap: () => setState(() => _kind = '')),
                for (final g in v.shop) RewardsChoice(label: g.label, selected: _kind == g.kind, onTap: () => setState(() => _kind = g.kind)),
              ],
            ),
          ),
        ),
      if (!hasItems && v.upcoming.isEmpty) _empty(l.rewardsEmptyShop),
      for (final g in groups)
        if (g.items.isNotEmpty) ...[
          _head(g.label, count: g.items.length),
          CardGrid(
            wide: g.wide,
            children: [
              for (final it in g.items)
                ItemCard(
                  api: api,
                  item: it,
                  wide: g.wide || it.wide,
                  onTap: () => _buy(it),
                  footer: it.kind == 'theme' ? _previewButton(it) : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      if (_kind.isEmpty && v.upcoming.isNotEmpty) ...[
        _head(l.rewardsComingSoon, count: v.upcoming.length),
        CardGrid(wide: false, children: [for (final it in v.upcoming) ItemCard(api: api, item: it, wide: false, dim: true)]),
      ],
    ];
  }

  Widget _previewButton(RewardsItem it) => OutlinedButton(
    style: OutlinedButton.styleFrom(minimumSize: const Size(64, 38)),
    onPressed: () => _preview(it),
    child: Text(context.l10n.rewardsPreview),
  );

  List<Widget> _collection(AppLocalizations l, RewardsView v) {
    final t = tokensOf(context);
    return [
      _head(l.rewardsSlots),
      Text(l.rewardsCollectionSub, style: TextStyle(color: t.muted)),
      const SizedBox(height: 10),
      for (final s in v.slots) Padding(padding: const EdgeInsets.only(bottom: 8), child: _slot(l, s)),
      const SizedBox(height: 12),
      if (v.mine.isEmpty) ...[
        _empty(l.rewardsEmptyInventory),
        Row(
          children: [
            OutlinedButton(onPressed: () => _go(_Tab.missions), child: Text(l.rewardsTabMissions)),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _go(_Tab.shop), child: Text(l.rewardsTabShop)),
          ],
        ),
      ],
      for (final g in v.mine) ...[
        _head(g.label, count: g.tiles.length + g.items.length),
        ..._tileList(g.tiles, TileMode.mine),
        if (g.items.isNotEmpty)
          CardGrid(
            wide: g.wide,
            children: [
              for (final it in g.items)
                ItemCard(
                  api: api,
                  item: it,
                  wide: g.wide || it.wide,
                  showPrice: false,
                  footer: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // A game cosmetic is worn in its game, not here: say which game instead of offering Equip.
                      if (it.kind == 'game_cosmetic')
                        Text(it.where, style: Theme.of(context).textTheme.bodySmall)
                      else
                        EquipButton(
                          equipped: it.equipped,
                          disabled: _frozen || _busy,
                          onPressed: () => _equip(it.kind, it.id, it.name, clear: it.equipped),
                        ),
                      if (it.kind == 'theme') ...[const SizedBox(height: 6), _previewButton(it)],
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 16),
      ],
    ];
  }

  Widget _slot(AppLocalizations l, RewardsSlot s) {
    final t = tokensOf(context);
    return RewardsCard(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (s.empty)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: t.paper2, borderRadius: BorderRadius.circular(radiusCard - 4), border: Border.all(color: t.line)),
              )
            else
              RewardsImage(api: api, path: s.img, width: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.label, style: TextStyle(color: t.muted, fontSize: 12.5)),
                  Text(s.empty ? l.rewardsSlotNone : s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (!s.empty)
              TextButton(
                onPressed: _frozen || _busy ? null : () => _equip(s.kind, '', s.name, clear: true),
                child: Text(l.rewardsUnequip),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _settings(AppLocalizations l, RewardsView v) {
    final t = tokensOf(context);
    return [
      _head(l.rewardsSettings),
      Text(l.rewardsSettingsSub, style: TextStyle(color: t.muted)),
      const SizedBox(height: 10),
      Panel(
        child: Column(
          children: [
            SwitchListTile(
              value: _showcase,
              onChanged: _busy ? null : (x) => setState(() => _showcase = x),
              title: Text(l.rewardsShowcase),
              subtitle: Text(l.rewardsShowcaseHint),
            ),
            const Divider(),
            SwitchListTile(
              value: _paused,
              onChanged: _busy ? null : (x) => setState(() => _paused = x),
              title: Text(l.rewardsPause),
              subtitle: Text(l.rewardsPauseHint),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _busy ? null : _saveSettings, child: Text(l.rewardsSave)),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// The ladder (or single mission) in full: every tier with its state, and
  /// the tile's own action underneath.
  void _openLadder(RewardsTile tile, TileMode mode) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _LadderSheet(
        api: api,
        tile: tile,
        mode: mode,
        frozen: _frozen,
        onClaim: () {
          Navigator.pop(ctx);
          _claim(tile);
        },
        onEquip: () {
          Navigator.pop(ctx);
          _equip('badge', tile.equipItem, tile.label.isEmpty ? tile.name : tile.label, clear: tile.equipped);
        },
      ),
    );
  }
}

class _LadderSheet extends StatelessWidget {
  const _LadderSheet({
    required this.api,
    required this.tile,
    required this.mode,
    required this.frozen,
    required this.onClaim,
    required this.onEquip,
  });
  final OpenPakApi api;
  final RewardsTile tile;
  final TileMode mode;
  final bool frozen;
  final VoidCallback onClaim, onEquip;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = tokensOf(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RewardsImage(api: api, path: tile.img, width: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tile.name, style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(tile.progress, style: TextStyle(color: t.ink2)),
                      if (tile.complete) Padding(padding: const EdgeInsets.only(top: 4), child: RewardsBadge(l.rewardsCompleted, state: RowState.ok)),
                      if (tile.pips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: TierPips(pips: tile.pips, earned: tile.earned)),
                    ],
                  ),
                ),
              ],
            ),
            if (tile.description.isNotEmpty) ...[const SizedBox(height: 12), Text(tile.description)],
            if (tile.tiers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(l.rewardsLadder, style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final r in tile.tiers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      RewardsImage(api: api, path: r.img, width: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.finish, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              r.points.isEmpty ? r.target : '${r.target} · ${r.points}',
                              style: TextStyle(color: t.muted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (r.state == 'earned')
                        RewardsBadge(l.rewardsTierEarned, state: RowState.ok)
                      else if (r.ready)
                        RewardsBadge(l.rewardsMReady, state: RowState.beta)
                      else if (r.state == 'current')
                        RewardsBadge(l.rewardsMProgress)
                      else
                        RewardsBadge(l.rewardsLocked),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            if (mode == TileMode.work && tile.ready)
              FilledButton(onPressed: frozen ? null : onClaim, child: Text(tile.claimText.isEmpty ? l.rewardsClaim : tile.claimText))
            else if (mode == TileMode.mine)
              EquipButton(equipped: tile.equipped, disabled: frozen, onPressed: onEquip),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l.rewardsDlgClose)),
          ],
        ),
      ),
    );
  }
}

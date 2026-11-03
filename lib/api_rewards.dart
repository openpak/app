part of 'api.dart';

// Rewards and themes: GET /me/rewards and friends. The server words every text
// in the caller's language and gives pictures as site paths; this file only
// reads that shape. Fields are read defensively: a newer server may add or
// drop one, and a missing field must not blank the whole screen.

String _rs(Object? v) => v is String ? v : '';
int _ri(Object? v) => v is num ? v.toInt() : 0;
bool _rb(Object? v) => v == true;
List<Map<String, dynamic>> _rl(Object? v) =>
    v is List ? [for (final e in v) if (e is Map<String, dynamic>) e] : const [];

/// One rung of a badge ladder.
class RewardsTier {
  RewardsTier({
    required this.finish,
    required this.img,
    required this.target,
    required this.points,
    required this.state,
    required this.ready,
  });
  final String finish, img, target, points;

  /// earned, current or locked.
  final String state;
  final bool ready;

  factory RewardsTier.fromJson(Map<String, dynamic> j) => RewardsTier(
    finish: _rs(j['finish']),
    img: _rs(j['img']),
    target: _rs(j['target']),
    points: _rs(j['points']),
    state: _rs(j['state']),
    ready: _rb(j['ready']),
  );
}

/// A mission tile: one mission, or a ladder showing the tier being worked on.
class RewardsTile {
  RewardsTile({
    required this.key,
    required this.name,
    required this.label,
    required this.description,
    required this.img,
    required this.state,
    required this.percent,
    required this.progress,
    required this.reward,
    required this.claimText,
    required this.missionId,
    required this.period,
    required this.pips,
    required this.earned,
    required this.tiers,
    required this.single,
    required this.equipped,
    required this.equipItem,
    required this.complete,
  });
  final String key, name, label, description, img, progress, reward, claimText, missionId, period, equipItem;

  /// progress, ready, earned or done.
  final String state;
  final int percent, earned;
  final List<bool> pips;
  final List<RewardsTier> tiers;
  final bool single, equipped, complete;

  bool get ready => state == 'ready';
  bool get isLadder => tiers.isNotEmpty || pips.isNotEmpty;

  factory RewardsTile.fromJson(Map<String, dynamic> j) => RewardsTile(
    key: _rs(j['key']),
    name: _rs(j['name']),
    label: _rs(j['label']),
    description: _rs(j['description']),
    img: _rs(j['img']),
    state: _rs(j['state']),
    percent: _ri(j['percent']).clamp(0, 100),
    progress: _rs(j['progress']),
    reward: _rs(j['reward']),
    claimText: _rs(j['claim_text']),
    missionId: _rs(j['mission_id']),
    period: _rs(j['period']),
    pips: j['pips'] is List ? [for (final p in j['pips'] as List) p == true] : const [],
    earned: _ri(j['earned']),
    tiers: [for (final t in _rl(j['tiers'])) RewardsTier.fromJson(t)],
    single: _rb(j['single']),
    equipped: _rb(j['equipped']),
    equipItem: _rs(j['equip_item']),
    complete: _rb(j['complete']),
  );
}

/// A shop or collection item.
class RewardsItem {
  RewardsItem({
    required this.id,
    required this.kind,
    required this.kindLabel,
    required this.name,
    required this.description,
    required this.img,
    required this.wide,
    required this.price,
    required this.need,
    required this.after,
    required this.affordable,
    required this.owned,
    required this.equipped,
    required this.limited,
    required this.where,
    required this.soon,
    required this.when,
  });
  final String id, kind, kindLabel, name, description, img, where, when;
  final bool wide, affordable, owned, equipped, limited, soon;

  /// Null when the item has no price (it cannot be bought).
  final int? price;

  /// Points still missing; 0 when the balance covers it.
  final int need, after;

  factory RewardsItem.fromJson(Map<String, dynamic> j) => RewardsItem(
    id: _rs(j['id']),
    kind: _rs(j['kind']),
    kindLabel: _rs(j['kind_label']),
    name: _rs(j['name']),
    description: _rs(j['description']),
    img: _rs(j['img']),
    wide: _rb(j['wide']),
    price: j['price'] is num ? (j['price'] as num).toInt() : null,
    need: _ri(j['need']),
    after: _ri(j['after']),
    affordable: _rb(j['affordable']),
    owned: _rb(j['owned']),
    equipped: _rb(j['equipped']),
    limited: _rb(j['limited']),
    where: _rs(j['where']),
    soon: _rb(j['soon']),
    when: _rs(j['when']),
  );
}

/// A shelf of one kind: items, and for My items also earned ladder tiles.
class RewardsGroup {
  RewardsGroup({required this.kind, required this.label, required this.wide, required this.tiles, required this.items});
  final String kind, label;
  final bool wide;
  final List<RewardsTile> tiles;
  final List<RewardsItem> items;

  factory RewardsGroup.fromJson(Map<String, dynamic> j) => RewardsGroup(
    kind: _rs(j['kind']),
    label: _rs(j['label']),
    wide: _rb(j['wide']),
    tiles: [for (final t in _rl(j['tiles'])) RewardsTile.fromJson(t)],
    items: [for (final i in _rl(j['items'])) RewardsItem.fromJson(i)],
  );
}

/// One line of the points history.
class RewardsEntry {
  RewardsEntry({required this.img, required this.title, required this.sub, required this.delta, required this.points});
  final String img, title, sub, points;
  final int delta;

  factory RewardsEntry.fromJson(Map<String, dynamic> j) => RewardsEntry(
    img: _rs(j['img']),
    title: _rs(j['title']),
    sub: _rs(j['sub']),
    delta: _ri(j['delta']),
    points: _rs(j['points']),
  );
}

/// An equip slot (badge, profile icon, theme).
class RewardsSlot {
  RewardsSlot({required this.kind, required this.label, required this.id, required this.name, required this.img});
  final String kind, label, id, name, img;
  bool get empty => id.isEmpty;

  factory RewardsSlot.fromJson(Map<String, dynamic> j) => RewardsSlot(
    kind: _rs(j['kind']),
    label: _rs(j['label']),
    id: _rs(j['id']),
    name: _rs(j['name']),
    img: _rs(j['img']),
  );
}

/// The whole Rewards screen set.
class RewardsView {
  RewardsView({
    required this.balance,
    required this.frozen,
    required this.paused,
    required this.showcasePublic,
    required this.todayPoints,
    required this.todayCap,
    required this.todayPercent,
    required this.capReached,
    required this.more,
    required this.playTime,
    required this.owned,
    required this.ready,
    required this.affordable,
    required this.nextKind,
    required this.nextText,
    required this.badge,
    required this.slots,
    required this.readyTiles,
    required this.tiles,
    required this.done,
    required this.ledger,
    required this.shop,
    required this.upcoming,
    required this.mine,
  });
  final int balance, todayPoints, todayCap, todayPercent, more, owned, ready, affordable;
  final bool frozen, paused, showcasePublic, capReached;
  final String playTime, nextKind, nextText;
  final RewardsSlot? badge;
  final List<RewardsSlot> slots;
  final List<RewardsTile> readyTiles, tiles, done;
  final List<RewardsEntry> ledger;
  final List<RewardsGroup> shop, mine;
  final List<RewardsItem> upcoming;

  /// The equipped slot of [kind], or null.
  RewardsSlot? slot(String kind) {
    for (final s in slots) {
      if (s.kind == kind && !s.empty) return s;
    }
    return null;
  }

  factory RewardsView.fromJson(Map<String, dynamic> j) => RewardsView(
    balance: _ri(j['balance']),
    frozen: _rb(j['frozen']),
    paused: _rb(j['paused']),
    showcasePublic: _rb(j['showcase_public']),
    todayPoints: _ri(j['today_points']),
    todayCap: _ri(j['today_cap']),
    todayPercent: _ri(j['today_percent']).clamp(0, 100),
    capReached: _rb(j['cap_reached']),
    more: _ri(j['more']),
    playTime: _rs(j['play_time']),
    owned: _ri(j['owned']),
    ready: _ri(j['ready']),
    affordable: _ri(j['affordable']),
    nextKind: _rs(j['next_kind']),
    nextText: _rs(j['next_text']),
    badge: j['badge'] is Map<String, dynamic> ? RewardsSlot.fromJson(j['badge'] as Map<String, dynamic>) : null,
    slots: [for (final s in _rl(j['slots'])) RewardsSlot.fromJson(s)],
    readyTiles: [for (final t in _rl(j['ready_tiles'])) RewardsTile.fromJson(t)],
    tiles: [for (final t in _rl(j['tiles'])) RewardsTile.fromJson(t)],
    done: [for (final t in _rl(j['done'])) RewardsTile.fromJson(t)],
    ledger: [for (final e in _rl(j['ledger'])) RewardsEntry.fromJson(e)],
    shop: [for (final g in _rl(j['shop'])) RewardsGroup.fromJson(g)],
    upcoming: [for (final i in _rl(j['upcoming'])) RewardsItem.fromJson(i)],
    mine: [for (final g in _rl(j['mine'])) RewardsGroup.fromJson(g)],
  );
}

/// A Rewards theme as the server validated it: colour tokens for light and
/// dark, named like the website's custom properties (paper, ink-2, accent...).
class RewardsTheme {
  RewardsTheme({required this.id, required this.name, required this.light, required this.dark});
  final String id, name;
  final Map<String, String> light, dark;

  static Map<String, String> _tokens(Object? v) => v is Map
      ? {for (final e in v.entries) if (e.key is String && e.value is String) e.key as String: e.value as String}
      : const {};

  factory RewardsTheme.fromJson(Map<String, dynamic> j) =>
      RewardsTheme(id: _rs(j['id']), name: _rs(j['name']), light: _tokens(j['light']), dark: _tokens(j['dark']));
}

extension RewardsApi on OpenPakApi {
  /// GET /me/rewards. A deployment without the rewards service answers 503
  /// `rewards_unavailable`; callers show that calmly, not as a failure.
  Future<RewardsView> rewards() async =>
      RewardsView.fromJson(await _decode(await _http.get(_uri('/me/rewards'), headers: _headers())));

  /// GET /me/rewards/theme: the equipped theme, or null (none equipped).
  Future<RewardsTheme?> equippedTheme() async {
    final body = await _decode(await _http.get(_uri('/me/rewards/theme'), headers: _headers()));
    final t = body['theme'];
    return t is Map<String, dynamic> ? RewardsTheme.fromJson(t) : null;
  }

  /// GET /themes/{id}: any shop theme's tokens, public, for a preview.
  Future<RewardsTheme> shopTheme(String id) async => RewardsTheme.fromJson(
    await _decode(
      await _http.get(
        Uri.parse('$baseUrl/themes/${Uri.encodeComponent(id)}'),
        headers: _headers(auth: false),
      ),
    ),
  );

  /// POST /me/rewards/claim: the points paid out.
  Future<int> claimReward(String mission, String period) async {
    final body = await _decode(
      await _http.post(
        _uri('/me/rewards/claim'),
        headers: _headers(json: true),
        body: jsonEncode({'mission': mission, 'period': period}),
      ),
    );
    return _ri(body['points']);
  }

  /// POST /me/rewards/redeem. [idempotencyKey] is one per purchase attempt and
  /// is reused on a retry, so a lost answer cannot buy the item twice.
  Future<void> redeemReward(String item, {required String idempotencyKey}) async {
    await _decode(
      await _http.post(
        _uri('/me/rewards/redeem'),
        headers: {..._headers(json: true), 'Idempotency-Key': idempotencyKey},
        body: jsonEncode({'item': item}),
      ),
    );
  }

  /// POST /me/rewards/equip. An empty [item] empties the slot.
  Future<void> equipReward(String slot, String item) => _post('/me/rewards/equip', {'slot': slot, 'item': item});

  /// POST /me/rewards/settings.
  Future<void> saveRewardsSettings({required bool showcase, required bool paused}) =>
      _post('/me/rewards/settings', {'showcase': showcase, 'paused': paused});
}

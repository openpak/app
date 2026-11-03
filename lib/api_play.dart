part of 'api.dart';

// Trophies, play activity, rankings and the companion tabs of a game.

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

DateTime? _time(Object? v) {
  final t = v is String ? DateTime.tryParse(v) : null;
  return t == null || t.year < 1971
      ? null
      : t; // Go's zero time means "not set"
}

List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    ((v as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(f)
        .toList(growable: false);

/// One figure of a [CompanionCard]. [key] is a stable id the app words itself.
class CardStat {
  CardStat({required this.key, required this.value, this.n = 0});
  factory CardStat.fromJson(Map<String, dynamic> j) => CardStat(
    key: j['key'] as String? ?? '',
    value: j['value'] as String? ?? '',
    n: _int(j['n']),
  );
  final String key;
  final String value;
  final int n;
}

/// One line of a card: a game, a trophy set, a listing. [percent] is 0..100 for a bar, -1 for none.
class CardRow {
  CardRow({
    required this.title,
    this.sub = '',
    this.value = '',
    this.percent = -1,
  });
  factory CardRow.fromJson(Map<String, dynamic> j) => CardRow(
    title: j['title'] as String? ?? '',
    sub: j['sub'] as String? ?? '',
    value: j['value'] as String? ?? '',
    percent: j['percent'] == null ? -1 : _int(j['percent']),
  );
  final String title;
  final String sub;
  final String value;
  final int percent;
}

/// The website's shared card: headline figures and a list. Serves a game's own stats,
/// its listings and the PS3 trophies.
class CompanionCard {
  CompanionCard({
    this.heading = '',
    this.stats = const [],
    this.rows = const [],
    this.linked = false,
  });
  factory CompanionCard.fromJson(Map<String, dynamic> j) => CompanionCard(
    heading: j['heading'] as String? ?? '',
    stats: _list(j['stats'], CardStat.fromJson),
    rows: _list(j['rows'], CardRow.fromJson),
    linked: j['linked'] == true,
  );
  final String heading;
  final List<CardStat> stats;
  final List<CardRow> rows;

  /// False when the account has no identity on the game's network yet.
  final bool linked;
}

/// A catalogue title that has companion pages, and which ones.
class CompanionTitle {
  CompanionTitle({
    required this.slug,
    required this.name,
    this.console = '',
    this.status = '',
    this.titleId = '',
    this.features = const [],
  });
  factory CompanionTitle.fromJson(Map<String, dynamic> j) => CompanionTitle(
    slug: j['slug'] as String? ?? '',
    name: j['name'] as String? ?? '',
    console: j['console'] as String? ?? '',
    status: j['status'] as String? ?? '',
    titleId: j['title_id'] as String? ?? '',
    features: ((j['features'] as List?) ?? const [])
        .map((e) => '$e')
        .toList(growable: false),
  );
  final String slug;
  final String name;
  final String console;
  final String status;
  final String titleId;

  /// `rankings`, `stats`, `listings`.
  final List<String> features;
}

/// A game with leaderboards (GET /rankings).
class RankedGame {
  RankedGame({
    required this.slug,
    required this.name,
    this.console = '',
    this.boards = 0,
  });
  factory RankedGame.fromJson(Map<String, dynamic> j) => RankedGame(
    slug: j['slug'] as String? ?? '',
    name: j['name'] as String? ?? '',
    console: j['console'] as String? ?? '',
    boards: _int(j['boards']),
  );
  final String slug;
  final String name;
  final String console;
  final int boards;
}

/// One selectable board: a course, a mode, a season.
class RankBoard {
  RankBoard({
    required this.id,
    required this.label,
    this.unit = '',
    this.season = '',
  });
  factory RankBoard.fromJson(Map<String, dynamic> j) => RankBoard(
    id: j['id'] as String? ?? '',
    label: j['label'] as String? ?? '',
    unit: j['unit'] as String? ?? '',
    season: j['season'] as String? ?? '',
  );
  final String id;
  final String label;
  final String unit;
  final String season;
}

/// One row of a board. [display] is how the game shows the value.
class RankEntry {
  RankEntry({
    required this.rank,
    required this.name,
    this.value = 0,
    this.display = '',
    this.region = '',
    this.note = '',
    this.me = false,
    this.avatar,
  });
  factory RankEntry.fromJson(Map<String, dynamic> j) => RankEntry(
    rank: _int(j['rank']),
    name: j['name'] as String? ?? '',
    value: _int(j['value']),
    display: j['display'] as String? ?? '',
    region: j['region'] as String? ?? '',
    note: j['note'] as String? ?? '',
    me: j['me'] == true,
    avatar: (j['avatar'] as String?)?.isEmpty ?? true
        ? null
        : j['avatar'] as String,
  );
  final int rank;
  final String name;
  final int value;
  final String display;
  final String region;
  final String note;
  final bool me;

  /// Site-relative; run it through [OpenPakApi.absolute].
  final String? avatar;
}

/// A window of one board, with the signed-in player's own slice in [around].
class RankingPage {
  RankingPage({
    this.boards = const [],
    this.board = '',
    this.label = '',
    this.entries = const [],
    this.around = const [],
    this.total = 0,
    this.offset = 0,
    this.limit = 0,
  });
  factory RankingPage.fromJson(Map<String, dynamic> j) => RankingPage(
    boards: _list(j['boards'], RankBoard.fromJson),
    board: j['board'] as String? ?? '',
    label: j['label'] as String? ?? '',
    entries: _list(j['entries'], RankEntry.fromJson),
    around: _list(j['around'], RankEntry.fromJson),
    total: _int(j['total']),
    offset: _int(j['offset']),
    limit: _int(j['limit']),
  );
  final List<RankBoard> boards;
  final String board;
  final String label;
  final List<RankEntry> entries;
  final List<RankEntry> around;
  final int total;
  final int offset;
  final int limit;

  bool get hasPrev => offset > 0;
  bool get hasNext => limit > 0 && offset + limit < total;
}

/// One game in the play history.
class ActivityTitle {
  ActivityTitle({
    this.network = '',
    this.titleId = '',
    this.title = '',
    this.sessions = 0,
    this.seconds = 0,
    this.last,
  });
  factory ActivityTitle.fromJson(Map<String, dynamic> j) => ActivityTitle(
    network: j['network'] as String? ?? '',
    titleId: j['title_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    sessions: _int(j['sessions']),
    seconds: _int(j['seconds']),
    last: _time(j['last_played']),
  );
  final String network;
  final String titleId;

  /// Empty when the catalogue does not know the id.
  final String title;
  final int sessions;
  final int seconds;
  final DateTime? last;
}

/// GET /me/activity: every game the network has a session for, on every network.
class PlayActivity {
  PlayActivity({
    this.titles = const [],
    this.totalSeconds = 0,
    this.sessions = 0,
  });
  factory PlayActivity.fromJson(Map<String, dynamic> j) => PlayActivity(
    titles: _list(j['titles'], ActivityTitle.fromJson),
    totalSeconds: _int(j['total_seconds']),
    sessions: _int(j['sessions']),
  );
  final List<ActivityTitle> titles;
  final int totalSeconds;
  final int sessions;

  /// Newest first, as the website lists them.
  List<ActivityTitle> get newestFirst => [...titles]
    ..sort(
      (a, b) => (b.last ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        a.last ?? DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
}

extension PlayApi on OpenPakApi {
  /// GET /me/trophies (bearer).
  Future<CompanionCard> trophies() async => CompanionCard.fromJson(
    await _decode(await _http.get(_uri('/me/trophies'), headers: _headers())),
  );

  /// GET /me/activity (bearer).
  Future<PlayActivity> playActivity() async => PlayActivity.fromJson(
    await _decode(await _http.get(_uri('/me/activity'), headers: _headers())),
  );

  /// GET /rankings: the games that have boards.
  Future<List<RankedGame>> rankedGames() async => _list(
    (await _decode(
      await _http.get(_uri('/rankings'), headers: _headers()),
    ))['games'],
    RankedGame.fromJson,
  );

  /// GET /companion/titles: the catalogue titles with companion pages.
  Future<List<CompanionTitle>> companionTitles() async => _list(
    (await _decode(
      await _http.get(_uri('/companion/titles'), headers: _headers()),
    ))['titles'],
    CompanionTitle.fromJson,
  );

  /// GET /companion/titles/{slug}
  Future<CompanionTitle> companionTitle(String slug) async =>
      CompanionTitle.fromJson(
        await _decode(
          await _http.get(
            _uri('/companion/titles/${Uri.encodeComponent(slug)}'),
            headers: _headers(),
          ),
        ),
      );

  /// GET /companion/titles/{slug}/rankings. With the bearer the player's own
  /// rows come back marked, and [RankingPage.around] when they are off the page.
  Future<RankingPage> companionRankings(
    String slug, {
    String? board,
    int offset = 0,
  }) async {
    final q = {
      if (board != null && board.isNotEmpty) 'board': board,
      if (offset > 0) 'offset': '$offset',
    };
    final u = _uri(
      '/companion/titles/${Uri.encodeComponent(slug)}/rankings',
    ).replace(queryParameters: q.isEmpty ? null : q);
    return RankingPage.fromJson(
      await _decode(await _http.get(u, headers: _headers())),
    );
  }

  /// GET /companion/titles/{slug}/stats (bearer).
  Future<CompanionCard> companionStats(String slug) async =>
      CompanionCard.fromJson(
        await _decode(
          await _http.get(
            _uri('/companion/titles/${Uri.encodeComponent(slug)}/stats'),
            headers: _headers(),
          ),
        ),
      );

  /// GET /companion/titles/{slug}/listings
  Future<CompanionCard> companionListings(String slug) async =>
      CompanionCard.fromJson(
        await _decode(
          await _http.get(
            _uri('/companion/titles/${Uri.encodeComponent(slug)}/listings'),
            headers: _headers(),
          ),
        ),
      );
}

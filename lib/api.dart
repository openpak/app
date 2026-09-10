/// The OpenPak mobile API, as published in the website's openapi.yaml.
///
/// Hand-written rather than generated: the surface is thirteen endpoints of
/// JSON in and JSON out, and a generated dart-dio client would bring dio,
/// built_value and a build_runner step to model it. The contract stays the
/// source of truth — every method below names the path it implements, and the
/// server has a test that fails when a served route is missing from the spec.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thrown for any non-success reply. [unauthorized] is separated because it is
/// the one the UI must act on: the token died, so the person is signed out.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  bool get unauthorized => statusCode == 401;
  @override
  String toString() => message;
}

class Account {
  Account({
    required this.id,
    required this.displayName,
    this.friendCode,
    this.country = '',
    this.birthday = '',
    this.avatarUrl,
    this.linkedPlatforms = const [],
  });
  final String id;
  final String displayName;

  /// Present only once a console is linked.
  final String? friendCode;
  final String country;
  final String birthday;

  /// Null when the account has never chosen one — the caller shows its own
  /// fallback rather than a broken image.
  final String? avatarUrl;
  final List<String> linkedPlatforms;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['account_id'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    friendCode: j['friend_code'] as String?,
    country: j['country'] as String? ?? '',
    birthday: j['birthday'] as String? ?? '',
    avatarUrl: j['avatar_url'] as String?,
    linkedPlatforms: ((j['linked_platforms'] as List?) ?? const [])
        .map((e) => (e as Map<String, dynamic>)['namespace'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false),
  );
}

/// One of the built-in avatars.
class AvatarChoice {
  AvatarChoice({required this.id, required this.url});
  final String id;
  final String url;
}

/// A signed-in device, as the core sees it. Revoking one signs that device out.
class WebSession {
  WebSession({required this.id, this.createdAt, this.expiresAt});
  final String id;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  factory WebSession.fromJson(Map<String, dynamic> j) => WebSession(
    id: j['id'] as String? ?? '',
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
    expiresAt: DateTime.tryParse(j['expires_at'] as String? ?? ''),
  );
}

/// Friend requests in both directions. Outgoing ones cannot be acted on here —
/// they are waiting on the other person.
class FriendRequests {
  FriendRequests({required this.incoming, required this.outgoing});
  final List<Friend> incoming;
  final List<Friend> outgoing;
}

class Friend {
  Friend({
    required this.accountId,
    required this.displayName,
    required this.online,
    this.titleId,
    this.since,
  });
  final String accountId;
  final String displayName;

  /// Whether they hold a live session right now. The fields below are only
  /// present when this is true.
  final bool online;
  final String? titleId;
  final DateTime? since;

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
    accountId: j['account_id'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    online: j['online'] as bool? ?? false,
    titleId: j['title_id'] as String?,
    since: j['since'] == null ? null : DateTime.tryParse(j['since'] as String),
  );
}

class Invitation {
  Invitation({
    required this.id,
    required this.from,
    required this.titleId,
    required this.expiresAt,
  });
  final String id;
  final String from;
  final String titleId;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);

  factory Invitation.fromJson(Map<String, dynamic> j) => Invitation(
    id: j['invitation_id'] as String? ?? '',
    from: j['from'] as String? ?? '',
    titleId: j['title_id'] as String? ?? '',
    expiresAt:
        DateTime.tryParse(j['expires_at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// A votable catalog entry: a game (kind "title") or a network feature
/// (kind "feature"). The same row the website's /titles and /features pages
/// show, reached over the API. Votes/voted are per-viewer projections, not
/// stored fields — voted is false when signed out.
class CatalogItem {
  CatalogItem({
    required this.id,
    required this.kind,
    required this.name,
    this.console = '',
    this.category = '',
    this.backend = '',
    this.status = '',
    this.notes = '',
    this.votes = 0,
    this.voted = false,
  });

  /// Kept as a String regardless of whether the server emits a JSON number or
  /// string — it is only ever echoed back in the vote path, never math.
  final String id;
  final String kind; // "title" | "feature"
  final String name;
  final String console;
  final String category;
  final String backend;
  final String status;
  final String notes;
  final int votes;
  final bool voted;

  bool get isTitle => kind == 'title';

  /// A row after a vote toggle: the count and voted flag change, the rest
  /// stays. Lets the list update one item without a full reload.
  CatalogItem withVote({required int votes, required bool voted}) => CatalogItem(
    id: id,
    kind: kind,
    name: name,
    console: console,
    category: category,
    backend: backend,
    status: status,
    notes: notes,
    votes: votes,
    voted: voted,
  );

  factory CatalogItem.fromJson(Map<String, dynamic> j) => CatalogItem(
    id: j['id']?.toString() ?? '',
    kind: j['kind'] as String? ?? 'title',
    name: j['name'] as String? ?? '',
    console: j['console'] as String? ?? '',
    category: j['category'] as String? ?? '',
    backend: j['backend'] as String? ?? '',
    status: j['status'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    votes: (j['votes'] as num?)?.toInt() ?? 0,
    voted: j['voted'] as bool? ?? false,
  );
}

class OpenPakApi {
  OpenPakApi({required this.baseUrl, http.Client? client, this.token})
    : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  /// The bearer. Held in memory only; persistence is the caller's job, so that
  /// this class never decides where a credential is written.
  String? token;

  /// Called once when the server rejects the bearer. A dead token is dead for
  /// every screen at once, so this is handled here rather than in each of
  /// them: without it a stale token leaves every tab saying "could not load"
  /// with no way back to the sign-in form.
  void Function()? onUnauthorized;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Map<String, String> _headers({bool json = false}) => {
    if (token != null) 'Authorization': 'Bearer $token',
    if (json) 'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> _decode(http.Response r) async {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return {};
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    var message = 'Request failed (${r.statusCode})';
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['error'] is String) message = body['error'];
    } catch (_) {
      // A non-JSON error body is a proxy or an outage, not something to show.
    }
    if (r.statusCode == 401 && token != null) {
      token = null;
      onUnauthorized?.call();
    }
    throw ApiException(r.statusCode, message);
  }

  /// POST /token — mints the bearer and keeps it on this instance.
  Future<String> signIn(String email, String password) async {
    final r = await _http.post(
      _uri('/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final body = await _decode(r);
    final t = body['token'] as String?;
    if (t == null || t.isEmpty) {
      throw ApiException(r.statusCode, 'The server returned no token');
    }
    token = t;
    return t;
  }

  /// DELETE /token — revokes it server-side; the core session goes with it.
  Future<void> signOut() async {
    try {
      await _http.delete(_uri('/token'), headers: _headers());
    } on ApiException {
      // Already invalid server-side: signing out locally is still correct.
    } finally {
      token = null;
    }
  }

  /// GET /me
  Future<Account> me() async =>
      Account.fromJson(await _decode(await _http.get(_uri('/me'), headers: _headers())));

  /// GET /me/friends — carries presence.
  Future<List<Friend>> friends() async {
    final body = await _decode(
      await _http.get(_uri('/me/friends'), headers: _headers()),
    );
    final list = (body['friends'] as List?) ?? const [];
    return list
        .map((e) => Friend.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// GET /me/invitations — reading this consumes nothing.
  Future<List<Invitation>> invitations() async {
    final body = await _decode(
      await _http.get(_uri('/me/invitations'), headers: _headers()),
    );
    final list = (body['invitations'] as List?) ?? const [];
    return list
        .map((e) => Invitation.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// POST /me/invitations/decline. False means it was already gone, which is
  /// not a failure worth showing anyone.
  Future<bool> decline(String invitationId) async {
    final body = await _decode(
      await _http.post(
        _uri('/me/invitations/decline'),
        headers: _headers(json: true),
        body: jsonEncode({'invitation_id': invitationId}),
      ),
    );
    return body['declined'] as bool? ?? false;
  }

  /// POST /me/profile — every field optional; an empty one is left alone.
  Future<void> updateProfile({
    String? displayName,
    String? country,
    String? birthday,
  }) => _post('/me/profile', {
    if (displayName != null) 'display_name': displayName,
    if (country != null) 'country': country,
    if (birthday != null) 'birthday': birthday,
  });

  /// GET /avatars — the built-ins the website offers.
  Future<List<AvatarChoice>> avatarChoices() async {
    final body = await _decode(
      await _http.get(_uri('/avatars'), headers: _headers()),
    );
    return ((body['avatars'] as List?) ?? const [])
        .map(
          (e) => AvatarChoice(
            id: (e as Map<String, dynamic>)['id'] as String? ?? '',
            url: e['url'] as String? ?? '',
          ),
        )
        .toList(growable: false);
  }

  /// POST /me/avatar
  Future<void> chooseAvatar(String preset) =>
      _post('/me/avatar', {'preset': preset});

  /// Absolute URL for a path the API returned relative to the site.
  String absolute(String path) => '$baseUrl$path';

  /// GET /me/friends/requests
  Future<FriendRequests> friendRequests() async {
    final body = await _decode(
      await _http.get(_uri('/me/friends/requests'), headers: _headers()),
    );
    List<Friend> read(String key) => ((body[key] as List?) ?? const [])
        .map((e) => Friend.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return FriendRequests(incoming: read('incoming'), outgoing: read('outgoing'));
  }

  /// POST /me/friends/requests — add by friend code, in either the display
  /// form (SW-xxxx-xxxx-xxxx) or bare.
  Future<void> addFriend(String friendCode) => _post('/me/friends/requests', {
    'friend_code': friendCode,
  });

  /// POST /me/friends/requests/accept
  Future<void> acceptFriend(String accountId) =>
      _post('/me/friends/requests/accept', {'account_id': accountId});

  /// POST /me/friends/remove
  Future<void> removeFriend(String accountId) =>
      _post('/me/friends/remove', {'account_id': accountId});

  /// POST /me/friends/block — also removes the friendship.
  Future<void> blockAccount(String accountId) =>
      _post('/me/friends/block', {'account_id': accountId});

  /// GET /me/sessions
  Future<List<WebSession>> sessions() async {
    final body = await _decode(
      await _http.get(_uri('/me/sessions'), headers: _headers()),
    );
    return ((body['sessions'] as List?) ?? const [])
        .map((e) => WebSession.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// DELETE /me/sessions/{id} — signs that device out.
  Future<void> revokeSession(String id) async {
    await _decode(
      await _http.delete(
        _uri('/me/sessions/${Uri.encodeComponent(id)}'),
        headers: _headers(),
      ),
    );
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    await _decode(
      await _http.post(
        _uri(path),
        headers: _headers(json: true),
        body: jsonEncode(body),
      ),
    );
  }

  /// GET /requests — the votable catalog (titles and features). Auth optional;
  /// without a bearer every row's `voted` is false. `whether signed in` is the
  /// only thing the bearer changes here, so the same list backs both states.
  Future<List<CatalogItem>> requests() async {
    final body = await _decode(
      await _http.get(_uri('/requests'), headers: _headers()),
    );
    return ((body['items'] as List?) ?? const [])
        .map((e) => CatalogItem.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// POST /requests/{id}/vote — toggles this account's vote and returns the
  /// fresh count. Auth required; a second call removes it (idempotent, no
  /// separate DELETE). The response carries the new count, so a row updates
  /// without a re-fetch.
  Future<({int votes, bool voted})> vote(String id) async {
    final body = await _decode(
      await _http.post(
        _uri('/requests/${Uri.encodeComponent(id)}/vote'),
        headers: _headers(json: true),
      ),
    );
    return (
      votes: (body['votes'] as num?)?.toInt() ?? 0,
      voted: body['voted'] as bool? ?? false,
    );
  }

  /// POST /me/push — registers this install for notifications.
  Future<void> registerPush(String deviceToken, {String platform = 'fcm'}) async {
    await _decode(
      await _http.post(
        _uri('/me/push'),
        headers: _headers(json: true),
        body: jsonEncode({'token': deviceToken, 'platform': platform}),
      ),
    );
  }

  /// DELETE /me/push
  Future<void> forgetPush(String deviceToken) async {
    await _decode(
      await _http.delete(
        _uri('/me/push?token=${Uri.encodeQueryComponent(deviceToken)}'),
        headers: _headers(),
      ),
    );
  }

  void close() => _http.close();
}

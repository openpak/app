/// The OpenPak mobile API, as published in the website's openapi.yaml.
///
/// Hand-written rather than generated: the surface is thirteen endpoints of
/// JSON in and JSON out, and a generated dart-dio client would bring dio,
/// built_value and a build_runner step to model it. The contract stays the
/// source of truth — every method below names the path it implements, and the
/// server has a test that fails when a served route is missing from the spec.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Thrown for any non-success reply. [unauthorized] is separated because it is
/// the one the UI must act on: the token died, so the person is signed out.
///
/// [message] is English, for logs; the UI shows the translation of [code]
/// (see apiErrorText in l10n.dart). [code] is null from a server older than
/// the error codes, and for failures the client raises itself.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.code, this.fromServer = false, this.path});
  final int statusCode;
  final String message;
  final String? code;

  /// Where in the sent document the server found the fault, dotted
  /// (`customSettings.ageRestriction.ratingAge`); null when it did not say.
  final String? path;

  /// Whether [message] is the server's own words rather than a placeholder.
  final bool fromServer;
  bool get unauthorized => statusCode == 401;
  @override
  String toString() => message;
}

/// POST /token answered 202: the password was right and the account wants a
/// second factor. Redeem [challenge] with [OpenPakApi.signInSecondFactor]. Not
/// a failure, but thrown so that every existing caller of signIn keeps its
/// shape and cannot mistake "no token yet" for a signed-in state.
class TwoFactorRequired implements Exception {
  TwoFactorRequired(this.challenge);

  /// Single use, valid ten minutes, burned after five wrong codes.
  final String challenge;
}

/// How the website reads the one code field: six digits are from the
/// authenticator app, anything else is a recovery code.
({String? code, String? recoveryCode}) splitSecondFactor(String typed) {
  final digits = typed.trim().replaceAll(' ', '');
  if (RegExp(r'^[0-9]{6}$').hasMatch(digits)) return (code: digits, recoveryCode: null);
  return (code: null, recoveryCode: typed.trim());
}

class Account {
  Account({
    required this.id,
    required this.displayName,
    this.friendCode,
    this.friendCodes = const [],
    this.country = '',
    this.birthday = '',
    this.avatarUrl,
    this.linkedPlatforms = const [],
    this.email = '',
    this.emailVerified = true,
    this.twoFactorEnabled = false,
  });
  final String id;
  final String displayName;

  /// Present only once a console is linked.
  final String? friendCode;

  /// Every code the account can be added by, in the website banner's order
  /// (OpenPak, Switch, Wii U NNID, 3DS). [label] is the server's English, for
  /// kinds the app has no word of its own for.
  final List<({String kind, String label, String code})> friendCodes;
  final String country;
  final String birthday;

  /// Null when the account has never chosen one — the caller shows its own
  /// fallback rather than a broken image.
  final String? avatarUrl;
  final List<String> linkedPlatforms;

  /// False until the address is confirmed. A server that does not say is
  /// taken at its word elsewhere, so absent reads as confirmed rather than
  /// nagging about something nobody reported.
  final bool emailVerified;
  final bool twoFactorEnabled;

  /// Empty when the server could not say (older servers, or the core was not asked).
  final String email;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['account_id'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    friendCode: j['friend_code'] as String?,
    // friend_codes is website v0.55.1; before it, the two codes it replaces.
    friendCodes: j['friend_codes'] is List
        ? [
            for (final c in (j['friend_codes'] as List).whereType<Map<String, dynamic>>())
              if (_nonEmpty(c['code']) != null)
                (kind: c['kind'] as String? ?? '', label: c['label'] as String? ?? '', code: c['code'] as String),
          ]
        : [
            if (_nonEmpty(j['openpak_code']) case final c?) (kind: 'openpak', label: 'OpenPak', code: c),
            if (_nonEmpty(j['friend_code']) case final c?) (kind: 'switch', label: 'Switch', code: c),
          ],
    country: j['country'] as String? ?? '',
    birthday: j['birthday'] as String? ?? '',
    avatarUrl: j['avatar_url'] as String?,
    linkedPlatforms: ((j['linked_platforms'] as List?) ?? const [])
        .map((e) => (e as Map<String, dynamic>)['namespace'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false),
    email: j['email'] as String? ?? '',
    emailVerified: j['email_verified'] != false,
    twoFactorEnabled: j['two_factor_enabled'] == true,
  );
}

/// Someone this account blocked. They cannot send requests, messages or
/// invitations until unblocked.
class BlockedAccount {
  BlockedAccount({required this.accountId, required this.displayName, this.blockedAt});
  final String accountId;
  final String displayName;
  final DateTime? blockedAt;

  factory BlockedAccount.fromJson(Map<String, dynamic> j) => BlockedAccount(
    accountId: j['account_id'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    blockedAt: DateTime.tryParse(j['blocked_at'] as String? ?? ''),
  );
}

/// One published news article, as the website's landing page shows it.
class NewsArticle {
  NewsArticle({
    required this.slug,
    required this.title,
    required this.summary,
    required this.body,
    this.publishedAt,
  });
  final String slug;
  final String title;

  /// The first paragraph of the body.
  final String summary;

  /// Plain text; paragraphs are separated by a blank line.
  final String body;
  final DateTime? publishedAt;

  factory NewsArticle.fromJson(Map<String, dynamic> j) => NewsArticle(
    slug: j['slug'] as String? ?? '',
    title: j['title'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    body: j['body'] as String? ?? '',
    publishedAt: DateTime.tryParse(j['published_at'] as String? ?? ''),
  );
}

/// What two-factor setup hands back: the key to type into an authenticator
/// app, and the same key as a link an app can open.
class TwoFactorSecret {
  TwoFactorSecret({required this.secret, required this.otpauthUri});
  final String secret;
  final String otpauthUri;
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

class ChatMessage {
  ChatMessage({required this.id, required this.from, required this.kind, required this.body, required this.sentAt});
  final int id;
  final String from;
  final String kind;
  final String body;
  final DateTime sentAt;

  /// Plain text; anything else (an invite, say) is shown by its kind, which the
  /// UI words, as the website does.
  bool get isText => kind.isEmpty || kind == 'text';

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: (j['id'] as num?)?.toInt() ?? 0,
    from: j['from_account'] as String? ?? '',
    kind: j['kind'] as String? ?? '',
    body: j['body'] as String? ?? '',
    sentAt: DateTime.fromMillisecondsSinceEpoch(((j['sent_at_unix'] as num?)?.toInt() ?? 0) * 1000),
  );
}

class Conversation {
  Conversation({required this.peer, required this.newest});
  final String peer;
  final ChatMessage newest;
}

/// Players online, in total and per console network (namespace → players).
class NetworkStatus {
  NetworkStatus({required this.playersOnline, required this.networks});
  final int playersOnline;
  final Map<String, int> networks;
}

class Friend {
  Friend({
    required this.accountId,
    required this.displayName,
    required this.online,
    this.titleId,
    this.namespace,
    this.since,
    this.avatarUrl,
    this.platform,
    this.client,
    this.label,
    this.titleName,
  });
  final String accountId;
  final String displayName;

  /// Whether they hold a live session right now. The fields below are only
  /// present when this is true.
  final bool online;
  final String? titleId;

  /// The account core's link namespace the session is on ("switch", "wiiu",
  /// "3ds", ...). Present exactly when [titleId] and [since] are.
  final String? namespace;
  final DateTime? since;

  /// The URL of the friend's avatar image, relative to the server root.
  /// Null when the account has never chosen one.
  final String? avatarUrl;

  /// Where the session is, from website presence (v0.50+): the console family
  /// ("switch", "wiiu", "3ds"), the client on it ("ryujinx", "eden",
  /// "citron", "cemu", "azahar", or the console itself), and the name to
  /// show for that ("Ryujinx", "Wii U", ...). Null from an older server, and
  /// when empty, so a caller only ever checks for null.
  final String? platform;
  final String? client;
  final String? label;

  /// The game's name as the website knows it; null when it does not.
  final String? titleName;

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
    accountId: j['account_id'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    online: j['online'] as bool? ?? false,
    titleId: j['title_id'] as String?,
    namespace: j['namespace'] as String?,
    since: j['since'] == null ? null : DateTime.tryParse(j['since'] as String),
    avatarUrl: j['avatar_url'] as String?,
    platform: _nonEmpty(j['platform']),
    client: _nonEmpty(j['client']),
    label: _nonEmpty(j['label']),
    titleName: _nonEmpty(j['title_name']),
  );
}

/// A string field that may be absent, null, not a string, or empty: the
/// value, or null.
String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

/// One console under parental controls, as the app lists it. The pairing code is
/// there only while it is still live: the server drops a dead one rather than let
/// a screen show a code someone would type. The PIN is not here: it is fetched
/// on its own, only when a parent asks to see it.
class ParentalDevice {
  ParentalDevice({
    required this.moonId,
    required this.paired,
    required this.pairingCode,
    required this.expiresAt,
    required this.hasSetting,
    this.nickname = '',
    this.named = false,
    this.serialNumber = '',
    this.firmware = '',
    this.setting = const {},
    this.players = const [],
    this.syncedAt,
    this.synced,
    this.wrongPinAttempts = const [],
  });
  final String moonId;
  final bool paired;
  final String pairingCode;
  final DateTime? expiresAt;
  final bool hasSetting;

  /// The name to show: the parent's, else one the server makes from the
  /// serial number ("Switch ···0001"), else empty. The console never sends
  /// a name of its own.
  final String nickname;

  /// Whether [nickname] is one the parent chose.
  final bool named;

  /// Empty where the server has none, as from one older than naming.
  final String serialNumber;
  final String firmware;

  /// The setting document as the console is served it, in the console's own
  /// shape (study §5b). Kept whole rather than modelled, so nothing in it is
  /// lost on the way through.
  final Map<String, dynamic> setting;
  final List<({String id, String nickname})> players;

  /// The console's last sync receipt; null when it has never synced.
  final DateTime? syncedAt;

  /// Whether the console holds the current document; null from a server that
  /// does not say.
  final bool? synced;

  /// Wrong PINs typed on the console, newest first.
  final List<DateTime> wrongPinAttempts;

  bool get waiting => !paired && pairingCode.isNotEmpty;

  factory ParentalDevice.fromJson(Map<String, dynamic> j) => ParentalDevice(
    moonId: j['moon_id'] as String? ?? '',
    paired: j['paired'] as bool? ?? false,
    pairingCode: j['pairing_code'] as String? ?? '',
    expiresAt: _unix(j['expires_at']),
    hasSetting: j['has_setting'] as bool? ?? false,
    nickname: _nonEmpty(j['nickname']) ?? '',
    named: j['named'] == true,
    serialNumber: _nonEmpty(j['serial_number']) ?? '',
    firmware: _nonEmpty(j['firmware']) ?? '',
    setting: j['setting'] is Map<String, dynamic> ? j['setting'] as Map<String, dynamic> : const {},
    players: [
      for (final p in (j['players'] as List? ?? const []).whereType<Map<String, dynamic>>())
        if (_nonEmpty(p['id']) case final id?) (id: id, nickname: p['nickname'] as String? ?? ''),
    ],
    syncedAt: _unix(j['synced_at']),
    synced: j['synced'] as bool?,
    wrongPinAttempts: [
      for (final t in j['wrong_pin_attempts'] as List? ?? const [])
        if (_unix(t) case final d?) d,
    ],
  );

  static DateTime? _unix(Object? v) => v is num && v > 0
      ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000)
      : null;
}

/// One day of play on a console: the date as the console's own calendar
/// named it, and each title's minutes.
class PlayDay {
  PlayDay({required this.date, required this.totalMinutes, this.titles = const []});
  final String date;
  final int totalMinutes;

  /// [name] is empty where the catalogue has none; show the id then.
  final List<({String titleId, String name, int minutes})> titles;

  factory PlayDay.fromJson(Map<String, dynamic> j) => PlayDay(
    date: j['date'] as String? ?? '',
    totalMinutes: (j['total_minutes'] as num?)?.toInt() ?? 0,
    titles: [
      for (final t in (j['titles'] as List? ?? const []).whereType<Map<String, dynamic>>())
        (
          titleId: t['title_id'] as String? ?? '',
          name: t['name'] as String? ?? '',
          minutes: (t['minutes'] as num?)?.toInt() ?? 0,
        ),
    ],
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
    this.titleId = '',
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

  /// The console's own title id, e.g. a Switch title's 16 hex digits. Empty
  /// for features and for a title the console side has none for. This is how
  /// a friend's presence title id is turned into a name elsewhere in the app.
  final String titleId;

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
    titleId: titleId,
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
    titleId: j['title_id'] as String? ?? '',
  );
}

/// One stored version of a save. Conflict means it was pushed from a base the
/// server had already moved past; it is kept, never dropped.
class SaveVersion {
  SaveVersion({
    required this.id,
    required this.number,
    this.parts = 1,
    required this.size,
    required this.conflict,
    required this.pinned,
    required this.backend,
    required this.createdAt,
    this.savedAt,
    this.device,
  });
  final int id;
  final int number;

  /// Console backups have several parts; only a one-part version downloads.
  final int parts;
  final int size;
  final bool conflict;
  final bool pinned;

  /// "local" is the OpenPak allowance; anything else is the player's own storage.
  final String backend;
  final DateTime createdAt;
  final DateTime? savedAt;
  final String? device;

  factory SaveVersion.fromJson(Map<String, dynamic> j) => SaveVersion(
    id: (j['id'] as num).toInt(),
    number: (j['number'] as num).toInt(),
    parts: (j['parts'] as num?)?.toInt() ?? 1,
    size: (j['size'] as num?)?.toInt() ?? 0,
    conflict: j['conflict'] == true,
    pinned: j['pinned'] == true,
    backend: (j['backend'] as String?) ?? 'local',
    createdAt: DateTime.parse(j['created_at'] as String),
    savedAt: j['saved_at'] is String ? DateTime.tryParse(j['saved_at'] as String) : null,
    device: j['device'] as String?,
  );
}

/// One title's saves on one platform, newest version first.
class CloudSave {
  CloudSave({required this.platform, required this.titleId, required this.versions, String? name, this.icon})
      : name = name ?? titleId;
  final String platform;
  final String titleId;

  /// The game's name when the website knows it, else the title id.
  final String name;

  /// A path on the website that draws the game's icon, when it has one.
  final String? icon;
  final List<SaveVersion> versions;

  factory CloudSave.fromJson(Map<String, dynamic> j) => CloudSave(
    platform: j['platform'] as String,
    titleId: j['title_id'] as String,
    name: (j['name'] as String?)?.isEmpty == true ? null : j['name'] as String?,
    icon: j['icon'] as String?,
    versions: ((j['versions'] as List?) ?? const [])
        .map((e) => SaveVersion.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
  );
}

class SavesUsage {
  SavesUsage({required this.allowanceUsed, required this.allowance, required this.total});
  final int allowanceUsed;
  final int allowance;
  final int total;

  factory SavesUsage.fromJson(Map<String, dynamic> j) => SavesUsage(
    allowanceUsed: (j['allowance_used'] as num?)?.toInt() ?? 0,
    allowance: (j['allowance'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
  );
}

class CloudSaves {
  CloudSaves({required this.saves, required this.usage});
  final List<CloudSave> saves;
  final SavesUsage usage;
}

/// The account's own storage, as the service reports it. The secret is never returned.
class SavesStorage {
  SavesStorage({
    required this.connected,
    this.kind,
    this.url,
    this.username,
    this.account,
    this.endpoint,
    this.region,
    this.bucket,
    this.prefix,
    this.accessKey,
    this.pathStyle = true,
    this.insecure = false,
    this.lastTestOk,
    this.lastError,
    this.moveState,
    required this.usage,
  });
  final bool connected;

  /// s3 | webdav | gdrive | onedrive.
  final String? kind;
  final String? url; // webdav
  final String? username; // webdav
  final String? account; // gdrive / onedrive: the e-mail the provider reported
  final String? endpoint;
  final String? region;
  final String? bucket;
  final String? prefix;
  final String? accessKey;
  final bool pathStyle;
  final bool insecure;
  final bool? lastTestOk;
  final String? lastError;
  final String? moveState;
  final SavesUsage usage;

  /// One line naming the storage, whatever its kind.
  String get name => switch (kind) {
    'webdav' => url ?? 'WebDAV',
    'gdrive' => account == null ? 'Google Drive' : 'Google Drive · $account',
    'onedrive' => account == null ? 'OneDrive' : 'OneDrive · $account',
    _ => '$bucket · $endpoint',
  };

  factory SavesStorage.fromJson(Map<String, dynamic> j) => SavesStorage(
    connected: j['connected'] == true,
    kind: j['kind'] as String?,
    url: j['url'] as String?,
    username: j['username'] as String?,
    account: (j['account'] as String?)?.isEmpty == true ? null : j['account'] as String?,
    endpoint: j['endpoint'] as String?,
    region: j['region'] as String?,
    bucket: j['bucket'] as String?,
    prefix: j['prefix'] as String?,
    accessKey: j['access_key'] as String?,
    pathStyle: j['path_style'] != false,
    insecure: j['insecure'] == true,
    lastTestOk: j['last_test_ok'] as bool?,
    lastError: (j['last_error'] as String?)?.isEmpty == true ? null : j['last_error'] as String?,
    moveState: (j['move_state'] as String?)?.isEmpty == true ? null : j['move_state'] as String?,
    usage: SavesUsage.fromJson((j['usage'] as Map<String, dynamic>?) ?? const {}),
  );
}

/// What the connect form submits: one kind and its fields. An empty secret keeps the stored
/// one on an edit.
class StorageConfig {
  StorageConfig.s3({
    required this.endpoint,
    required this.bucket,
    required this.accessKey,
    required this.secretKey,
    this.region = '',
    this.prefix = '',
    this.pathStyle = true,
    this.insecure = false,
  }) : kind = 's3', url = '', username = '', password = '';

  StorageConfig.webdav({required this.url, required this.username, required this.password})
      : kind = 'webdav', endpoint = '', bucket = '', accessKey = '', secretKey = '',
        region = '', prefix = '', pathStyle = true, insecure = false;

  final String kind;
  final String endpoint, bucket, accessKey, secretKey, region, prefix;
  final bool pathStyle, insecure;
  final String url, username, password;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (kind == 's3')
      's3': {
        'endpoint': endpoint,
        'region': region,
        'bucket': bucket,
        'prefix': prefix,
        'access_key': accessKey,
        'secret_key': secretKey,
        'path_style': pathStyle,
        'insecure': insecure,
      },
    if (kind == 'webdav')
      'webdav': {'url': url, 'username': username, 'password': password},
  };
}

/// Someone in a voice room: in the game with you, and maybe talking.
class VoiceMember {
  VoiceMember({required this.accountId, required this.displayName, this.inVoice = false});
  final String accountId;
  final String displayName;

  /// Connected to the room's voice chat right now.
  final bool inVoice;

  factory VoiceMember.fromJson(Map<String, dynamic> j) => VoiceMember(
    accountId: j['account_id'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    inVoice: j['in_voice'] == true,
  );
}

/// A voice room: the game you are in ([isGame]), or one made to be joined by
/// its six-character [code].
class VoiceRoom {
  VoiceRoom({required this.code, required this.kind, this.title = '', this.maxMembers = 8, this.members = const []});
  final String code;
  final String kind;

  /// The title server's name for the game (splatoon-2); empty for a code room.
  final String title;
  final int maxMembers;
  final List<VoiceMember> members;
  bool get isGame => kind == 'game';

  factory VoiceRoom.fromJson(Map<String, dynamic> j) => VoiceRoom(
    code: j['code'] as String? ?? '',
    kind: j['kind'] as String? ?? 'code',
    title: j['title'] as String? ?? '',
    maxMembers: (j['max_members'] as num?)?.toInt() ?? 8,
    members: ((j['members'] as List?) ?? const [])
        .map((e) => VoiceMember.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
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

  /// The app's language as a BCP-47 tag (pt-BR, de), sent as Accept-Language
  /// on every call: the website writes account e-mails in it.
  String? language;

  /// Called once when the server rejects the bearer. A dead token is dead for
  /// every screen at once, so this is handled here rather than in each of
  /// them: without it a stale token leaves every tab saying "could not load"
  /// with no way back to the sign-in form.
  void Function()? onUnauthorized;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Map<String, String> _headers({bool json = false, bool auth = true}) => {
    if (auth && token != null) 'Authorization': 'Bearer $token',
    if (language != null) 'Accept-Language': language!,
    if (json) 'Content-Type': 'application/json',
  };

  /// [signOutOn401] is false only where the server also answers 401 for a
  /// wrong two-factor code: a typo there must not cost the person their sign-in.
  Future<Map<String, dynamic>> _decode(http.Response r, {bool signOutOn401 = true}) async {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return {};
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    var message = 'Request failed (${r.statusCode})';
    String? code;
    String? path;
    var fromServer = false;
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['error'] is String) message = body['error'];
      if (body is Map && body['detail'] is String) message = body['detail'];
      if (body is Map && body['code'] is String) code = body['code'];
      if (body is Map && body['path'] is String) path = body['path'];
      fromServer = body is Map && (body['error'] is String || body['detail'] is String);
    } catch (_) {
      // A non-JSON error body is a proxy or an outage, not something to show.
    }
    if (r.statusCode == 401 && token != null && signOutOn401) {
      token = null;
      onUnauthorized?.call();
    }
    throw ApiException(r.statusCode, message, code: code, fromServer: fromServer, path: path);
  }

  /// POST /token — mints the bearer and keeps it on this instance. Throws
  /// [TwoFactorRequired] when the account asks for a code first.
  Future<String> signIn(String email, String password) async {
    final r = await _http.post(
      _uri('/token'),
      headers: _headers(json: true, auth: false),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _keepToken(r, await _decode(r));
  }

  /// POST /token/2fa — finishes a sign-in [signIn] answered with a challenge.
  /// [typed] is whatever the person entered: an authenticator code or a
  /// recovery code, told apart the way the website does. A 401 means the code
  /// was wrong or the challenge is spent; either way, sign in again.
  Future<String> signInSecondFactor(String challenge, String typed) async {
    final second = splitSecondFactor(typed);
    final r = await _http.post(
      _uri('/token/2fa'),
      headers: _headers(json: true, auth: false),
      body: jsonEncode({
        'challenge': challenge,
        if (second.code != null) 'code': second.code,
        if (second.recoveryCode != null) 'recovery_code': second.recoveryCode,
      }),
    );
    return _keepToken(r, await _decode(r));
  }

  String _keepToken(http.Response r, Map<String, dynamic> body) {
    if (r.statusCode == 202 && body['two_factor_required'] == true) {
      throw TwoFactorRequired(body['challenge'] as String? ?? '');
    }
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

  /// DELETE /me — ends the account. The password again, and for a two-factor
  /// account a current code or a recovery code; every bearer, this one
  /// included, stops working, so the caller signs out afterwards.
  Future<void> deleteAccount(String password, {String? code}) async {
    await _decode(await _http.delete(
      _uri('/me'),
      headers: _headers(json: true),
      body: jsonEncode({
        'password': password,
        if (code != null && code.isNotEmpty) 'code': code,
      }),
    ));
    token = null;
  }

  /// POST /me/email — a confirmation link goes to the new address; nothing
  /// changes until it is opened on the website.
  Future<void> changeEmail(String newEmail, String password) =>
      _post('/me/email', {'new_email': newEmail, 'password': password});

  /// POST /me/verify/resend — the same answer whether or not a mail went out.
  Future<void> resendVerification() => _post('/me/verify/resend', const {});

  /// POST /me/2fa/setup — asks for the password even though signed in.
  Future<TwoFactorSecret> twoFactorSetup(String password) async {
    final body = await _decode(await _http.post(
      _uri('/me/2fa/setup'),
      headers: _headers(json: true),
      body: jsonEncode({'password': password}),
    ));
    return TwoFactorSecret(
      secret: body['secret'] as String? ?? '',
      otpauthUri: body['otpauth_uri'] as String? ?? '',
    );
  }

  /// POST /me/2fa/enable — the ten recovery codes, shown once and never again.
  Future<List<String>> twoFactorEnable(String code) async {
    final body = await _decode(
      await _http.post(
        _uri('/me/2fa/enable'),
        headers: _headers(json: true),
        body: jsonEncode({'code': code.replaceAll(' ', '')}),
      ),
      signOutOn401: false,
    );
    return ((body['recovery_codes'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);
  }

  /// POST /me/2fa/disable — a recovery code counts as a code.
  Future<void> twoFactorDisable(String password, String code) async {
    await _decode(
      await _http.post(
        _uri('/me/2fa/disable'),
        headers: _headers(json: true),
        body: jsonEncode({'password': password, 'code': code.trim()}),
      ),
      signOutOn401: false,
    );
  }

  /// GET /news — public, newest first; empty when the deployment has none.
  Future<List<NewsArticle>> news({int limit = 3}) async {
    final body = await _decode(await _http.get(_uri('/news?limit=$limit'), headers: _headers(auth: false)));
    return ((body['articles'] as List?) ?? const [])
        .map((e) => NewsArticle.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

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


  /// GET /me/saves — every platform's saves under the account, with usage.
  Future<CloudSaves> saves() async {
    final body = await _decode(
      await _http.get(_uri('/me/saves'), headers: _headers()),
    );
    final list = (body['saves'] as List?) ?? const [];
    return CloudSaves(
      saves: list
          .map((e) => CloudSave.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      usage: SavesUsage.fromJson((body['usage'] as Map<String, dynamic>?) ?? const {}),
    );
  }


  /// GET /me/saves/storage
  Future<SavesStorage> savesStorage() async => SavesStorage.fromJson(
    await _decode(await _http.get(_uri('/me/saves/storage'), headers: _headers())),
  );

  /// PUT /me/saves/storage — the service tests the bucket before storing it.
  /// Returns the warning, if any (a bucket readable without credentials).
  Future<String?> connectStorage(StorageConfig cfg) async {
    final body = await _decode(await _http.put(
      _uri('/me/saves/storage'),
      headers: _headers(json: true),
      body: jsonEncode(cfg.toJson()),
    ));
    final w = body['warning'] as String?;
    return (w == null || w.isEmpty) ? null : w;
  }

  /// DELETE /me/saves/storage
  Future<void> disconnectStorage() async =>
      _decode(await _http.delete(_uri('/me/saves/storage'), headers: _headers()));

  /// POST /me/saves/versions/{id}/restore — make a version the current one; the old stays.
  Future<void> restoreSave(int id) => _post('/me/saves/versions/$id/restore', const {});

  /// DELETE /me/saves/versions/{id}
  Future<void> deleteSave(int id) async =>
      _decode(await _http.delete(_uri('/me/saves/versions/$id'), headers: _headers()));

  /// GET /me/saves/versions/{id} — one version's bytes.
  Future<Uint8List> downloadSave(int id) async {
    final r = await _http.get(_uri('/me/saves/versions/$id'), headers: _headers());
    await _decode(r.statusCode < 300 ? http.Response('', r.statusCode) : r); // throws on failure
    return r.bodyBytes;
  }

  /// POST /me/saves/storage/move — runs in the background; poll savesStorage().
  Future<void> moveSaves() => _post('/me/saves/storage/move', const {});

  /// GET /me/saves/storage/kinds — which kinds this deployment offers.
  Future<Map<String, bool>> storageKinds() async {
    final body = await _decode(
      await _http.get(_uri('/me/saves/storage/kinds'), headers: _headers()),
    );
    return body.map((k, v) => MapEntry(k, v == true));
  }

  /// GET /me/saves/storage/oauth/{provider}/url — the consent page to open in a browser; the
  /// website's callback finishes the connection for this account.
  Future<Uri> storageOAuthUrl(String provider) async {
    final body = await _decode(await _http.get(
      _uri('/me/saves/storage/oauth/${Uri.encodeComponent(provider)}/url'),
      headers: _headers(),
    ));
    return Uri.parse(body['url'] as String);
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

  /// POST /me/friends/requests — add by code. [kind] is openpak, switch,
  /// 3ds, wiiu or email (website v0.57.0); left out, the server reads an OP- code as OpenPak and anything else
  /// as Switch.
  Future<void> addFriend(String friendCode, {String? kind}) => _post('/me/friends/requests', {
    'friend_code': friendCode,
    'kind': ?kind,
  });

  /// POST /me/friends/requests/accept
  Future<void> acceptFriend(String accountId) =>
      _post('/me/friends/requests/accept', {'account_id': accountId});

  /// POST /me/friends/requests/decline — one already gone is not an error.
  Future<void> declineFriend(String accountId) =>
      _post('/me/friends/requests/decline', {'account_id': accountId});

  /// GET /me/blocked
  Future<List<BlockedAccount>> blocked() async {
    final body = await _decode(await _http.get(_uri('/me/blocked'), headers: _headers()));
    return ((body['blocked'] as List?) ?? const [])
        .map((e) => BlockedAccount.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// POST /me/friends/remove
  Future<void> removeFriend(String accountId) =>
      _post('/me/friends/remove', {'account_id': accountId});

  /// POST /me/friends/block — also removes the friendship.
  Future<void> blockAccount(String accountId) =>
      _post('/me/friends/block', {'account_id': accountId});

  /// POST /me/friends/unblock
  Future<void> unblockAccount(String accountId) =>
      _post('/me/friends/unblock', {'account_id': accountId});

  /// GET /status — public: who is online, per console network.
  Future<NetworkStatus> status() async {
    final body = await _decode(await _http.get(_uri('/status'), headers: _headers(auth: false)));
    return NetworkStatus(
      playersOnline: (body['players_online'] as num?)?.toInt() ?? 0,
      networks: {
        for (final n in (body['networks'] as List?) ?? const [])
          (n as Map)['namespace'] as String: (n['players'] as num?)?.toInt() ?? 0,
      },
    );
  }

  /// POST /register — public; the same answer whether or not the address is
  /// taken, and a verification mail follows.
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) => _post('/register', {
    'email': email,
    'password': password,
    'display_name': displayName,
  });

  /// POST /password/forgot — public; the mail links to the website's reset page.
  Future<void> forgotPassword(String email) =>
      _post('/password/forgot', {'email': email});

  /// POST /me/password — every other session and bearer ends; this one stays.
  Future<void> changePassword(String current, String next) => _post(
    '/me/password',
    {'current_password': current, 'new_password': next},
  );

  /// POST /me/links/wfc — a Wii or DS, by a friend code read off a game.
  Future<void> linkWfc(String friendCode) =>
      _post('/me/links/wfc', {'friend_code': friendCode});

  /// DELETE /me/links/{namespace}
  Future<void> unlink(String namespace) async => _decode(await _http.delete(
    _uri('/me/links/${Uri.encodeComponent(namespace)}'),
    headers: _headers(),
  ));

  /// POST /me/avatar, multipart — a PNG or JPEG of up to 4 MiB.
  Future<void> uploadAvatar(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest('POST', _uri('/me/avatar'))
      ..headers.addAll(_headers())
      ..files.add(http.MultipartFile.fromBytes('avatar', bytes, filename: filename));
    await _decode(await http.Response.fromStream(await _http.send(req)));
  }

  /// POST /crash-reports, multipart — `meta` (JSON) and an optional text
  /// `attachment`. Signed in, the bearer goes along so the report names the
  /// account; a 401 here never signs the app out.
  Future<void> sendCrashReport(Map<String, dynamic> meta, {String? attachment}) async {
    final req = http.MultipartRequest('POST', _uri('/crash-reports'))
      ..headers.addAll(_headers())
      ..fields['meta'] = jsonEncode(meta);
    if (attachment != null && attachment.isNotEmpty) {
      req.files.add(http.MultipartFile.fromString('attachment', attachment, filename: 'crash.txt'));
    }
    await _decode(await http.Response.fromStream(await _http.send(req)), signOutOn401: false);
  }

  /// GET /me/chat — one entry per peer, newest message first.
  Future<List<Conversation>> conversations() async {
    final body = await _decode(await _http.get(_uri('/me/chat'), headers: _headers()));
    return ((body['conversations'] as List?) ?? const [])
        .map((e) => Conversation(
              peer: (e as Map)['peer'] as String? ?? '',
              newest: ChatMessage.fromJson(e['newest'] as Map<String, dynamic>? ?? const {}),
            ))
        .toList(growable: false);
  }

  /// GET /me/chat/{peer} — oldest first; [after] fetches only newer ones.
  Future<List<ChatMessage>> chatHistory(String peer, {int after = 0}) async {
    final body = await _decode(await _http.get(
      _uri('/me/chat/${Uri.encodeComponent(peer)}${after > 0 ? '?after=$after' : ''}'),
      headers: _headers(),
    ));
    return ((body['messages'] as List?) ?? const [])
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// POST /me/chat/{peer}
  Future<ChatMessage> sendChat(String peer, String text) async {
    final body = await _decode(await _http.post(
      _uri('/me/chat/${Uri.encodeComponent(peer)}'),
      headers: _headers(json: true),
      body: jsonEncode({'body': text}),
    ));
    return ChatMessage.fromJson(body['message'] as Map<String, dynamic>? ?? const {});
  }

  /// GET /me/voice — the room of the game you are playing, or null.
  Future<VoiceRoom?> voiceCurrent() async {
    final body = await _decode(await _http.get(_uri('/me/voice'), headers: _headers()));
    final room = body['room'];
    return room is Map<String, dynamic> ? VoiceRoom.fromJson(room) : null;
  }

  /// POST /me/voice/rooms — a new room to share by its code.
  Future<VoiceRoom> createVoiceRoom() async {
    final body = await _decode(await _http.post(_uri('/me/voice/rooms'), headers: _headers()));
    return VoiceRoom.fromJson(body['room'] as Map<String, dynamic>? ?? const {});
  }

  /// GET /me/voice/rooms/{code} — checks a typed code before connecting.
  Future<VoiceRoom> voiceRoom(String code) async {
    final body = await _decode(await _http.get(
      _uri('/me/voice/rooms/${Uri.encodeComponent(code)}'),
      headers: _headers(),
    ));
    return VoiceRoom.fromJson(body['room'] as Map<String, dynamic>? ?? const {});
  }

  /// GET /me/voice/ws — the signaling socket's address; [voiceHeaders] carry the bearer.
  Uri voiceSocketUri(String code) {
    final u = _uri('/me/voice/ws');
    return u.replace(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {'code': code},
    );
  }

  Map<String, String> get voiceHeaders => _headers();

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

  /// GET /me/parental-controls — the consoles this account manages.
  Future<List<ParentalDevice>> parentalDevices() async {
    final body = await _decode(
      await _http.get(_uri('/me/parental-controls'), headers: _headers()),
    );
    return (((body['devices'] as List?) ?? const [])
        .map((e) => ParentalDevice.fromJson(e as Map<String, dynamic>))
        .toList(growable: false));
  }

  /// POST /me/parental-controls/pairing — a fresh code to type on the console.
  /// Asking again is how someone who walked away from the console gets one that
  /// is still alive, so this is not idempotent and is not meant to be.
  Future<ParentalDevice> parentalPair() async {
    final body = await _decode(
      await _http.post(_uri('/me/parental-controls/pairing'), headers: _headers(json: true)),
    );
    return ParentalDevice.fromJson({...body, 'paired': false, 'has_setting': false});
  }

  /// GET /me/parental-controls/{moon_id}/pin — the console's PIN, or null when
  /// the server holds none. The caller keeps it on screen only.
  Future<String?> parentalPin(String moonId) async {
    final r = await _http.get(
      _uri('/me/parental-controls/${Uri.encodeComponent(moonId)}/pin'),
      headers: _headers(),
    );
    if (r.statusCode == 404) return null;
    return _nonEmpty((await _decode(r))['unlock_code']);
  }

  /// GET /me/parental-controls/{moon_id}/players/{player_id}/image — the
  /// picture the console uploaded, or null when it sent none. Fetched rather
  /// than handed to Image.network, which would not carry the bearer.
  Future<Uint8List?> parentalPlayerImage(String moonId, String playerId) async {
    final r = await _http.get(
      _uri('/me/parental-controls/${Uri.encodeComponent(moonId)}/players/${Uri.encodeComponent(playerId)}/image'),
      headers: _headers(),
    );
    if (r.statusCode == 404) return null;
    await _decode(r.statusCode < 300 ? http.Response('', r.statusCode) : r); // throws on failure
    return r.bodyBytes;
  }

  /// PUT /me/parental-controls/{moon_id}/setting — the whole document, as the
  /// console will be served it. A 400 names the refused part in
  /// [ApiException.path]; nothing is stored then.
  Future<void> parentalSaveSetting(String moonId, Map<String, dynamic> setting) async {
    await _decode(
      await _http.put(
        _uri('/me/parental-controls/${Uri.encodeComponent(moonId)}/setting'),
        headers: _headers(json: true),
        body: jsonEncode({'setting': setting}),
      ),
    );
  }

  /// PUT /me/parental-controls/{moon_id}/name — the parent's name for the
  /// console, trimmed by the server; empty clears it. Never sent to the
  /// console.
  Future<void> parentalRename(String moonId, String name) async {
    await _decode(
      await _http.put(
        _uri('/me/parental-controls/${Uri.encodeComponent(moonId)}/name'),
        headers: _headers(json: true),
        body: jsonEncode({'name': name}),
      ),
    );
  }

  /// PUT /me/parental-controls/{moon_id}/pin — the console's next PIN. The
  /// console keeps its old one until it syncs.
  Future<void> parentalSetPin(String moonId, String pin) async {
    await _decode(
      await _http.put(
        _uri('/me/parental-controls/${Uri.encodeComponent(moonId)}/pin'),
        headers: _headers(json: true),
        body: jsonEncode({'unlock_code': pin}),
      ),
    );
  }

  /// DELETE /me/parental-controls/{moon_id} — off this account's list. The
  /// console is not told.
  Future<void> parentalRemove(String moonId) async {
    await _decode(
      await _http.delete(_uri('/me/parental-controls/${Uri.encodeComponent(moonId)}'), headers: _headers()),
    );
  }

  /// GET /me/parental-controls/{moon_id}/activity — play time per day, newest
  /// first. A server from before activity answers 404, which is none.
  Future<List<PlayDay>> parentalActivity(String moonId, {int days = 7}) async {
    final r = await _http.get(
      _uri('/me/parental-controls/${Uri.encodeComponent(moonId)}/activity?days=$days'),
      headers: _headers(),
    );
    if (r.statusCode == 404) return const [];
    return [
      for (final d in ((await _decode(r))['days'] as List? ?? const []).whereType<Map<String, dynamic>>())
        PlayDay.fromJson(d),
    ];
  }

  /// POST /me/parental-controls/unlock — the account password again, where the
  /// phone has no lock of its own to ask. 204 when right, 403 when not.
  Future<void> parentalUnlock(String password) => _post('/me/parental-controls/unlock', {'password': password});

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

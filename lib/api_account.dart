part of 'api.dart';

// Support tickets, Discord, region node operator and other account calls.

/// The files a ticket takes: one, at most this many bytes (the server's limit).
const ticketAttachmentLimit = 10 * 1024 * 1024;

class TicketAttachment {
  const TicketAttachment({required this.name, required this.size, required this.url});
  factory TicketAttachment.fromJson(Map<String, dynamic> j) => TicketAttachment(
    name: j['name'] as String? ?? '',
    size: (j['size'] as num?)?.toInt() ?? 0,
    url: j['url'] as String? ?? '',
  );
  final String name;
  final int size;

  /// Relative to the site; needs the bearer.
  final String url;
}

class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.fromStaff,
    required this.body,
    this.createdAt,
    this.attachment,
  });
  factory TicketMessage.fromJson(Map<String, dynamic> j) => TicketMessage(
    id: (j['id'] as num?)?.toInt() ?? 0,
    fromStaff: j['from'] == 'staff',
    body: j['body'] as String? ?? '',
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
    attachment: j['attachment'] is Map<String, dynamic>
        ? TicketAttachment.fromJson(j['attachment'] as Map<String, dynamic>)
        : null,
  );
  final int id;
  final bool fromStaff;
  final String body;
  final DateTime? createdAt;
  final TicketAttachment? attachment;
}

class Ticket {
  const Ticket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    this.messages = 0,
    this.createdAt,
    this.updatedAt,
    this.thread = const [],
  });
  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
    id: (j['id'] as num?)?.toInt() ?? 0,
    subject: j['subject'] as String? ?? '',
    category: j['category'] as String? ?? '',
    status: j['status'] as String? ?? 'open',
    messages: (j['messages'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '')?.toLocal(),
    thread: [
      for (final m in (j['thread'] as List? ?? const []).whereType<Map<String, dynamic>>())
        TicketMessage.fromJson(m),
    ],
  );
  final int id;
  final String subject, category;

  /// open: waiting on the team; waiting: answered; closed.
  final String status;
  final int messages;
  final DateTime? createdAt, updatedAt;

  /// Oldest first; only set by the single-ticket calls.
  final List<TicketMessage> thread;
}

/// GET /me/tickets
class TicketList {
  const TicketList({required this.tickets, required this.categories, required this.attachments});
  final List<Ticket> tickets;
  final List<String> categories;

  /// Whether this deployment keeps files.
  final bool attachments;
}

/// A file chosen to go with a ticket message.
typedef TicketUpload = ({Uint8List bytes, String name});

/// GET /me/discord
class DiscordLink {
  const DiscordLink({required this.configured, required this.linked, this.username = ''});
  factory DiscordLink.fromJson(Map<String, dynamic> j) => DiscordLink(
    configured: j['configured'] == true,
    linked: j['linked'] == true,
    username: j['username'] as String? ?? '',
  );
  final bool configured, linked;
  final String username;
}

/// Where the Wii U / 3DS console password comes from. [mode] is `sync` (the OpenPak password is
/// the console password), `custom` (a separate one), `incompatible` (the OpenPak password cannot
/// be typed on a Wii U and no separate one is set) or empty (not seen since this existed).
class ConsolePassword {
  const ConsolePassword({required this.nnid, required this.mode, this.min = 6, this.max = 16});
  factory ConsolePassword.fromJson(Map<String, dynamic> j) => ConsolePassword(
    nnid: j['nnid'] as String? ?? '',
    mode: j['mode'] as String? ?? '',
    min: (j['min'] as num?)?.toInt() ?? 6,
    max: (j['max'] as num?)?.toInt() ?? 16,
  );
  final String nnid, mode;
  final int min, max;
}

class OperatorLocation {
  const OperatorLocation({required this.code, required this.country, required this.city});
  final String code, country, city;
}

class OperatorServer {
  const OperatorServer({
    this.cores = 0,
    this.ramGb = 0,
    this.diskGb = 0,
    this.diskSsd = false,
    this.bandwidthMbps = 0,
    this.ipv6 = false,
    this.roles = const [],
  });
  factory OperatorServer.fromJson(Map<String, dynamic> j) => OperatorServer(
    cores: (j['cores'] as num?)?.toInt() ?? 0,
    ramGb: (j['ram_gb'] as num?)?.toInt() ?? 0,
    diskGb: (j['disk_gb'] as num?)?.toInt() ?? 0,
    diskSsd: j['disk_ssd'] == true,
    bandwidthMbps: (j['bandwidth_mbps'] as num?)?.toInt() ?? 0,
    ipv6: j['ipv6'] == true,
    roles: [for (final r in (j['roles'] as List? ?? const [])) '$r'],
  );
  Map<String, dynamic> toJson() => {
    'cores': cores,
    'ram_gb': ramGb,
    'disk_gb': diskGb,
    'disk_ssd': diskSsd,
    'bandwidth_mbps': bandwidthMbps,
    'ipv6': ipv6,
    'roles': roles,
  };
  final int cores, ramGb, diskGb, bandwidthMbps;
  final bool diskSsd, ipv6;
  final List<String> roles;
}

class OperatorApplication {
  const OperatorApplication({
    required this.id,
    required this.status,
    this.country = '',
    this.city = '',
    this.provider = '',
    this.adminNote = '',
    this.reply = '',
    this.servers = const [],
    this.updatedAt,
  });
  factory OperatorApplication.fromJson(Map<String, dynamic> j) => OperatorApplication(
    id: (j['id'] as num?)?.toInt() ?? 0,
    status: j['status'] as String? ?? 'pending',
    country: j['country'] as String? ?? '',
    city: j['city'] as String? ?? '',
    provider: j['provider'] as String? ?? '',
    adminNote: j['admin_note'] as String? ?? '',
    reply: j['reply'] as String? ?? '',
    servers: [
      for (final s in (j['servers'] as List? ?? const []).whereType<Map<String, dynamic>>())
        OperatorServer.fromJson(s),
    ],
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '')?.toLocal(),
  );
  final int id;

  /// pending, info, approved, rejected or waitlist.
  final String status;
  final String country, city, provider, adminNote, reply;
  final List<OperatorServer> servers;
  final DateTime? updatedAt;
}

/// GET /me/operator
class OperatorInfo {
  const OperatorInfo({
    this.inReview = false,
    this.roles = const [],
    this.maxServers = 4,
    this.termsUrl = '',
    this.requirements = const {},
    this.locations = const [],
    this.applications = const [],
  });
  factory OperatorInfo.fromJson(Map<String, dynamic> j) => OperatorInfo(
    inReview: j['in_review'] == true,
    roles: [for (final r in (j['roles'] as List? ?? const [])) '$r'],
    maxServers: (j['max_servers'] as num?)?.toInt() ?? 4,
    termsUrl: j['terms_url'] as String? ?? '',
    requirements: {
      for (final e in ((j['requirements'] as Map?) ?? const {}).entries)
        '${e.key}': (e.value is num) ? (e.value as num) : 0,
    },
    locations: [
      for (final l in (j['locations'] as List? ?? const []).whereType<Map<String, dynamic>>())
        OperatorLocation(
          code: l['code'] as String? ?? '',
          country: l['country'] as String? ?? '',
          city: l['city'] as String? ?? '',
        ),
    ],
    applications: [
      for (final a in (j['applications'] as List? ?? const []).whereType<Map<String, dynamic>>())
        OperatorApplication.fromJson(a),
    ],
  );
  final bool inReview;
  final List<String> roles;
  final int maxServers;
  final String termsUrl;

  /// node_cores, node_ram_gb, node_disk_gb, server_cores, server_ram_gb,
  /// server_bandwidth_mbps, availability_pct.
  final Map<String, num> requirements;
  final List<OperatorLocation> locations;
  final List<OperatorApplication> applications;
}

/// A 409 or 422 from the operator endpoints: [errors] are already worded in
/// the caller's language and are shown as given.
class OperatorRejected extends ApiException {
  OperatorRejected(super.statusCode, super.message, this.errors, {super.code});
  final List<String> errors;
}

extension OpenPakAccountApi on OpenPakApi {
  // ---- help tickets -------------------------------------------------------

  /// GET /me/tickets
  Future<TicketList> tickets() async {
    final b = await _decode(await _http.get(_uri('/me/tickets'), headers: _headers()));
    return TicketList(
      tickets: [
        for (final t in (b['tickets'] as List? ?? const []).whereType<Map<String, dynamic>>()) Ticket.fromJson(t),
      ],
      categories: [for (final c in (b['categories'] as List? ?? const [])) '$c'],
      attachments: b['attachments'] == true,
    );
  }

  /// GET /me/tickets/{id} — the ticket with its thread, oldest first.
  Future<Ticket> ticket(int id) async =>
      Ticket.fromJson(await _decode(await _http.get(_uri('/me/tickets/$id'), headers: _headers())));

  /// POST /me/tickets — JSON, or multipart when a file comes along.
  Future<Ticket> openTicket({
    required String subject,
    required String category,
    required String message,
    TicketUpload? attachment,
  }) async {
    final fields = {'subject': subject, 'category': category, 'message': message};
    return Ticket.fromJson(await _sendTicket('/me/tickets', fields, attachment));
  }

  /// POST /me/tickets/{id}/messages
  Future<TicketMessage> replyTicket(int id, String message, {TicketUpload? attachment}) async =>
      TicketMessage.fromJson(await _sendTicket('/me/tickets/$id/messages', {'message': message}, attachment));

  Future<Map<String, dynamic>> _sendTicket(String path, Map<String, String> fields, TicketUpload? file) async {
    if (file == null) {
      return _decode(await _http.post(_uri(path), headers: _headers(json: true), body: jsonEncode(fields)));
    }
    final req = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers())
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('attachment', file.bytes, filename: file.name));
    return _decode(await http.Response.fromStream(await _http.send(req)));
  }

  /// GET the `url` a ticket message carries — the file's bytes.
  Future<Uint8List> ticketAttachment(String url) async {
    final r = await _http.get(Uri.parse(absolute(url)), headers: _headers());
    await _decode(r.statusCode < 300 ? http.Response('', r.statusCode) : r); // throws on failure
    return r.bodyBytes;
  }

  // ---- Discord ------------------------------------------------------------

  /// GET /me/discord
  Future<DiscordLink> discord() async =>
      DiscordLink.fromJson(await _decode(await _http.get(_uri('/me/discord'), headers: _headers())));

  /// GET /me/wiiu/console-password — the Network ID to type on a Wii U or 3DS; null while the
  /// account has none yet or the server cannot say.
  Future<ConsolePassword?> consolePassword() async {
    final r = await _http.get(_uri('/me/wiiu/console-password'), headers: _headers());
    if (r.statusCode == 404 || r.statusCode == 503) return null;
    return ConsolePassword.fromJson(await _decode(r));
  }

  /// POST /me/wiiu/console-password — a separate console password, for an OpenPak password a Wii U
  /// cannot take. Asks for the OpenPak password again, and a code with two-factor authentication.
  Future<void> setConsolePassword(String current, String console, {String? code}) => _post(
    '/me/wiiu/console-password',
    {
      'current_password': current,
      'console_password': console,
      if (code != null && code.isNotEmpty) 'code': code,
    },
  );

  /// DELETE /me/discord
  Future<void> unlinkDiscord() async =>
      _decode(await _http.delete(_uri('/me/discord'), headers: _headers()));

  // ---- region node operator ----------------------------------------------

  /// 409 and 422 carry `errors`, already worded; everything else is plain.
  Future<Map<String, dynamic>> _operatorDecode(http.Response r) {
    if (r.statusCode == 409 || r.statusCode == 422) {
      try {
        final b = jsonDecode(r.body);
        if (b is Map && b['errors'] is List) {
          throw OperatorRejected(
            r.statusCode,
            b['error'] as String? ?? 'not accepted',
            [for (final e in b['errors'] as List) '$e'],
            code: b['code'] as String?,
          );
        }
      } on FormatException {
        // not JSON: the plain path below words it
      }
    }
    return _decode(r);
  }

  /// GET /me/operator — 503 means applications are off (operator_unavailable).
  Future<OperatorInfo> operatorInfo() async => OperatorInfo.fromJson(
    await _operatorDecode(await _http.get(_uri('/me/operator'), headers: _headers())),
  );

  /// POST /me/operator
  Future<void> operatorApply({
    required String location,
    required String city,
    required String provider,
    required String email,
    required String notes,
    required bool terms,
    required List<OperatorServer> servers,
  }) async => _operatorDecode(
    await _http.post(
      _uri('/me/operator'),
      headers: _headers(json: true),
      body: jsonEncode({
        'location': location,
        'city': city,
        'provider': provider,
        'email': email,
        'notes': notes,
        'terms': terms,
        'servers': [for (final s in servers) s.toJson()],
      }),
    ),
  );

  /// POST /me/operator/waitlist
  Future<void> operatorWaitlist({required String country, String city = '', required String email}) async =>
      _operatorDecode(
        await _http.post(
          _uri('/me/operator/waitlist'),
          headers: _headers(json: true),
          body: jsonEncode({'country': country, 'city': city, 'email': email}),
        ),
      );

  /// POST /me/operator/reply
  Future<void> operatorReply(int id, String reply) async =>
      _operatorDecode(await _http.post(
        _uri('/me/operator/reply'),
        headers: _headers(json: true),
        body: jsonEncode({'id': id, 'reply': reply}),
      ));

  // ---- profile text -------------------------------------------------------

  /// GET /me — the motto and bio, which the website's profile form edits.
  Future<({String motto, String bio})> profileText() async {
    final b = await _decode(await _http.get(_uri('/me'), headers: _headers()));
    return (motto: b['motto'] as String? ?? '', bio: b['bio'] as String? ?? '');
  }

  /// POST /me/profile with the motto (21 characters) and bio (499) only.
  Future<void> saveProfileText({required String motto, required String bio}) =>
      _post('/me/profile', {'motto': motto, 'bio': bio});
}

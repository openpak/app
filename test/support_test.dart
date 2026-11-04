import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/support_page.dart';
import 'package:openpak/theme.dart';

import 'localized.dart';

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

Map<String, Object?> _ticket(int id, String status, {List<Map<String, Object?>>? thread}) => {
  'id': id,
  'subject': 'Cannot sign in',
  'category': 'account',
  'status': status,
  'messages': thread?.length ?? 1,
  'created_at': '2026-11-01T10:00:00Z',
  'updated_at': '2026-11-02T10:00:00Z',
  if (thread != null) 'thread': thread,
};

Map<String, Object?> _msg(int id, String from, String body, {Map<String, Object?>? attachment}) => {
  'id': id,
  'from': from,
  'body': body,
  'created_at': '2026-11-01T10:00:00Z',
  'attachment': attachment,
};

void main() {
  late List<String> calls;
  late bool off;
  late bool files;
  late List<Map<String, Object?>> tickets;
  late Map<String, Object?> thread;

  OpenPakApi api() => OpenPakApi(
    baseUrl: 'https://openpak.test',
    token: 't',
    client: MockClient((req) async {
      final path = req.url.path.replaceFirst('/api/v1', '');
      calls.add('${req.method} $path ${req.headers['content-type']?.split(';').first ?? ''}'.trim());
      if (path.startsWith('/me/tickets') && off) {
        return _json({'error': 'help tickets are not available on this deployment', 'code': 'tickets_unavailable'}, 503);
      }
      if (path == '/pakka/state') return _json({'available': false, 'eligible': false, 'consent': false});
      if (path == '/me/tickets' && req.method == 'GET') {
        return _json({
          'tickets': tickets,
          'categories': ['account', 'network', 'switch', 'wiiu-3ds', 'emulator', 'saves', 'app', 'other'],
          'attachments': files,
        });
      }
      if (path == '/me/tickets' && req.method == 'POST') {
        return _json({..._ticket(9, 'open', thread: [_msg(1, 'you', 'It fails')]), 'subject': 'Hi'}, 201);
      }
      if (path == '/me/tickets/9') return _json({..._ticket(9, 'open', thread: [_msg(1, 'you', 'It fails')]), 'subject': 'Hi'});
      if (path == '/me/tickets/7/messages') return _json(_msg(3, 'you', 'More'), 201);
      if (path == '/me/tickets/7') return _json(thread);
      if (path == '/me/tickets/7/attachments/2') return http.Response('PNGDATA', 200);
      return _json({'error': 'nope'}, 404);
    }),
  );

  setUp(() {
    calls = [];
    off = false;
    files = true;
    tickets = [_ticket(7, 'waiting')];
    thread = _ticket(7, 'waiting', thread: [
      _msg(1, 'you', 'I cannot sign in'),
      _msg(2, 'staff', 'Try the reset link', attachment: {'name': 'steps.png', 'size': 7, 'url': '/api/v1/me/tickets/7/attachments/2'}),
    ]);
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(theme: openPakLight(), home: home));
    await tester.pumpAndSettle();
  }

  test('parsing: tickets, thread, attachment', () async {
    final a = api();
    final list = await a.tickets();
    expect(list.tickets.single.status, 'waiting');
    expect(list.categories.first, 'account');
    expect(list.attachments, isTrue);
    final t = await a.ticket(7);
    expect(t.thread.map((m) => m.fromStaff), [false, true]);
    expect(t.thread.last.attachment!.name, 'steps.png');
    expect(await a.ticketAttachment(t.thread.last.attachment!.url), utf8.encode('PNGDATA'));
  });

  test('a file makes the open and the reply multipart', () async {
    final a = api();
    final up = (bytes: Uint8List.fromList([1, 2, 3]), name: 'shot.png');
    await a.openTicket(subject: 'Hi', category: 'app', message: 'm', attachment: up);
    await a.replyTicket(7, 'more', attachment: up);
    expect(calls, contains('POST /me/tickets multipart/form-data'));
    expect(calls, contains('POST /me/tickets/7/messages multipart/form-data'));
  });

  testWidgets('list shows tickets with their status and a form with the server categories', (tester) async {
    await pump(tester, SupportPage(api: api()));
    expect(find.text('Cannot sign in'), findsOneWidget);
    expect(find.text('Answered'), findsOneWidget);
    expect(find.text('New request'), findsOneWidget);
    expect(find.text('Attach a file'), findsOneWidget);
  });


  // A 1x1 PNG, so Image.memory has something real to decode.
  final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

  Future<void> choose(WidgetTester tester, PlatformFile file) async {
    final before = ticketFilePicker;
    ticketFilePicker = () async => file;
    addTearDown(() => ticketFilePicker = before);
    await tester.tap(find.text('Attach a file'));
    await tester.pumpAndSettle();
  }

  testWidgets('any file type can be attached: a log shows its name and size, no image preview', (tester) async {
    await pump(tester, SupportPage(api: api()));
    await choose(tester, PlatformFile(name: 'crash.log', size: 2048, bytes: Uint8List(2048)));
    expect(find.text('crash.log'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    expect(find.byKey(const Key('attachment-preview')), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });

  testWidgets('an image attachment keeps its preview', (tester) async {
    await pump(tester, SupportPage(api: api()));
    await choose(tester, PlatformFile(name: 'shot.png', size: png.length, bytes: png));
    expect(find.text('shot.png'), findsOneWidget);
    expect(find.byKey(const Key('attachment-preview')), findsOneWidget);
  });

  testWidgets('a file over 10 MB is refused with a message and nothing is attached', (tester) async {
    await pump(tester, SupportPage(api: api()));
    await choose(tester, PlatformFile(name: 'huge.zip', size: ticketAttachmentLimit + 1));
    expect(find.text('That file is larger than 10 MB. Choose a smaller one.'), findsOneWidget);
    expect(find.text('huge.zip'), findsNothing);
    expect(find.text('Attach a file'), findsOneWidget);
  });

  testWidgets('exactly 10 MB is accepted, and the attached file is removable', (tester) async {
    await pump(tester, SupportPage(api: api()));
    await choose(tester, PlatformFile(name: 'edge.bin', size: ticketAttachmentLimit, bytes: Uint8List(ticketAttachmentLimit)));
    expect(find.text('edge.bin'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();
    expect(find.text('Attach a file'), findsOneWidget);
  });

  testWidgets('a chosen file goes out with the ticket as multipart', (tester) async {
    await pump(tester, SupportPage(api: api(), subject: 'Hi', category: 'app', message: 'It fails'));
    await choose(tester, PlatformFile(name: 'crash.log', size: 3, bytes: Uint8List.fromList([1, 2, 3])));
    await tester.ensureVisible(find.text('Send'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /me/tickets multipart/form-data'));
  });

  testWidgets('no attachment button when the deployment keeps no files', (tester) async {
    files = false;
    await pump(tester, SupportPage(api: api()));
    expect(find.text('Attach a file'), findsNothing);
  });

  testWidgets('503 tickets_unavailable is a calm message, not an error', (tester) async {
    off = true;
    await pump(tester, SupportPage(api: api()));
    expect(find.textContaining('not available right now'), findsOneWidget);
    expect(find.text('Could not load'), findsNothing);
  });

  testWidgets('opening a ticket posts JSON and lands in its thread', (tester) async {
    await pump(tester, SupportPage(api: api(), subject: 'Hi', category: 'account', message: 'It fails'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /me/tickets application/json'));
    expect(find.text('It fails'), findsOneWidget); // the thread of the new ticket
  });

  testWidgets('an incomplete form is not sent', (tester) async {
    await pump(tester, SupportPage(api: api()));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.startsWith('POST')), isEmpty);
  });

  testWidgets('the thread reads oldest first and a reply posts', (tester) async {
    await pump(tester, TicketPage(api: api(), ticket: Ticket.fromJson(_ticket(7, 'waiting'))));
    expect(find.text('I cannot sign in'), findsOneWidget);
    expect(find.text('Try the reset link'), findsOneWidget);
    expect(tester.getTopLeft(find.text('I cannot sign in')).dy, lessThan(tester.getTopLeft(find.text('Try the reset link')).dy));
    expect(find.text('OpenPak team'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'More');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Reply'));
    await tester.tap(find.widgetWithText(FilledButton, 'Reply'));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /me/tickets/7/messages application/json'));
  });

  testWidgets('an image attachment is fetched with the bearer and previewed', (tester) async {
    await pump(tester, TicketPage(api: api(), ticket: Ticket.fromJson(_ticket(7, 'waiting'))));
    await tester.tap(find.text('steps.png'));
    await tester.pumpAndSettle();
    expect(calls, contains('GET /me/tickets/7/attachments/2'));
    expect(find.text('Save or share'), findsOneWidget);
  });

  testWidgets('a closed ticket says a reply reopens it', (tester) async {
    thread = {...thread, 'status': 'closed'};
    await pump(tester, TicketPage(api: api(), ticket: Ticket.fromJson(_ticket(7, 'closed'))));
    expect(find.text('Reply to reopen this request'), findsOneWidget);
  });
}

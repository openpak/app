import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/updater.dart';

import 'localized.dart';

Map<String, Object?> release(
  String tag, {
  String body = 'Notes',
  List<Map<String, Object?>>? assets,
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/openpak/app/releases/tag/$tag',
  'body': body,
  'draft': false,
  'prerelease': false,
  'assets':
      assets ??
      [
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url': 'https://example.test/arm64.apk',
          'size': 5,
          'digest':
              'sha256:${sha256.convert(utf8.encode('hello')).toString().toUpperCase()}',
        },
        {
          'name': 'app-x86_64-release.apk',
          'browser_download_url': 'https://example.test/x.apk',
          'size': 1,
        },
      ],
};

UpdateChecker checker(
  String current,
  Map<String, Object?> latest, {
  int status = 200,
  List<int>? calls,
}) => UpdateChecker(
  current: current,
  client: MockClient((req) async {
    calls?.add(1);
    return http.Response(jsonEncode(latest), status);
  }),
);

void main() {
  test('versions compare numerically, not as text', () {
    Version v(String s) => Version.parse(s)!;
    expect(v('0.10.0') > v('0.9.9'), isTrue);
    expect(v('v1.0.0') > v('0.99.99'), isTrue);
    expect(v('0.23.0') > v('0.23.0'), isFalse);
    expect(v('0.22.0+38').compareTo(v('0.22.0')), 0);
    expect(v('0.22.1') > v('0.22.0'), isTrue);
    expect(Version.parse('nightly'), isNull);
    expect(Version.parse('1.2'), isNull);
  });

  test('a newer release is offered; the same or an older one is not', () async {
    expect(
      (await checker('0.22.0', release('v0.23.0')).check())?.version.toString(),
      '0.23.0',
    );
    expect(await checker('0.23.0', release('v0.23.0')).check(), isNull);
    expect(await checker('0.24.0', release('v0.23.0')).check(), isNull);
  });

  test('checks once per session', () async {
    final calls = <int>[];
    final c = checker('0.1.0', release('v0.23.0'), calls: calls);
    expect(await c.check(), isNotNull);
    expect(await c.check(), isNull);
    expect(calls.length, 1);
  });

  test('Later suppresses that version, not a newer one', () async {
    final c = checker('0.1.0', release('v0.23.0'));
    final r = (await c.check())!;
    expect(c.shouldOffer(r), isTrue);
    c.later(r);
    expect(c.shouldOffer(r), isFalse);
    expect(c.shouldOffer(ReleaseInfo.fromJson(release('v0.23.1'))!), isTrue);
    // A new app session is a new checker: asked again.
    expect(await checker('0.1.0', release('v0.23.0')).check(), isNotNull);
  });

  test('network and server failures are silent', () async {
    expect(
      await checker('0.1.0', release('v0.23.0'), status: 403).check(),
      isNull,
    );
    expect(
      await UpdateChecker(
        current: '0.1.0',
        client: MockClient((_) async => throw const SocketException('down')),
      ).check(),
      isNull,
    );
    expect(
      await UpdateChecker(
        current: '0.1.0',
        client: MockClient((_) async => http.Response('<html>', 200)),
      ).check(),
      isNull,
    );
  });

  test('drafts, pre-releases and odd tags are ignored', () {
    expect(
      ReleaseInfo.fromJson({...release('v0.23.0'), 'prerelease': true}),
      isNull,
    );
    expect(
      ReleaseInfo.fromJson({...release('v0.23.0'), 'draft': true}),
      isNull,
    );
    expect(ReleaseInfo.fromJson(release('nightly')), isNull);
    expect(ReleaseInfo.fromJson('x'), isNull);
  });

  test('the APK follows the phone ABI order and carries its digest', () {
    final r = ReleaseInfo.fromJson(release('v0.23.0'))!;
    expect(
      r.apkFor(['arm64-v8a', 'armeabi-v7a'])!.name,
      'app-arm64-v8a-release.apk',
    );
    expect(r.apkFor(['x86_64'])!.sha256, isNull);
    expect(r.apkFor(['armeabi-v7a']), isNull);
    expect(
      r.assets.first.sha256,
      sha256.convert(utf8.encode('hello')).toString(),
    );
  });

  test('notes are plain and short', () {
    expect(shortNotes('## v1\n\n- **Bold** `x`\n\n'), 'v1\n- Bold x');
    expect(shortNotes('a' * 800).length, lessThan(502));
  });

  group('download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('updater'));
    tearDown(() => dir.deleteSync(recursive: true));

    ReleaseAsset asset({int size = 5, String? hash}) => ReleaseAsset(
      name: 'a.apk',
      url: 'https://example.test/a.apk',
      size: size,
      sha256: hash ?? sha256.convert(utf8.encode('hello')).toString(),
    );
    http.Client serve(String body) => MockClient.streaming(
      (req, _) async =>
          http.StreamedResponse(Stream.value(utf8.encode(body)), 200),
    );

    test('a matching file is kept', () async {
      final f = File('${dir.path}/a.apk');
      await downloadVerified(serve('hello'), asset(), f);
      expect(f.readAsStringSync(), 'hello');
    });

    test('a wrong checksum or size is refused and deleted', () async {
      final f = File('${dir.path}/a.apk');
      await expectLater(
        downloadVerified(serve('HELLO'), asset(), f),
        throwsA(isA<UpdateFailure>()),
      );
      expect(f.existsSync(), isFalse);
      await expectLater(
        downloadVerified(serve('hello!'), asset(), f),
        throwsA(isA<UpdateFailure>()),
      );
      expect(f.existsSync(), isFalse);
    });
  });

  testWidgets('the dialog names the version and Later closes it', (
    tester,
  ) async {
    final c = checker('0.1.0', release('v0.23.0', body: 'Fixes things'));
    final r = (await tester.runAsync(c.check))!;
    late BuildContext ctx;
    await tester.pumpWidget(
      localizedApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    unawaited(offerUpdate(ctx, c, r));
    await tester.pumpAndSettle();
    expect(find.textContaining('0.23.0'), findsOneWidget);
    expect(find.text('Fixes things'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(c.shouldOffer(r), isFalse);
  });
}

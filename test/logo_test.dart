import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The app ships a copy of the website's icon.svg so the two cannot look
  // different. A copy is only as good as the thing that notices it went stale,
  // so when the website is checked out next door, compare them.
  test('the bundled logo matches the website', () {
    final upstream = File('../website/web/static/icon.svg');
    if (!upstream.existsSync()) {
      // A clean checkout of this repo alone: nothing to compare against.
      return;
    }
    final ours = File('assets/icon.svg');
    expect(ours.existsSync(), isTrue, reason: 'assets/icon.svg is missing');
    expect(
      ours.readAsBytesSync(),
      equals(upstream.readAsBytesSync()),
      reason: 'the logo has changed on the website; re-copy it and regenerate '
          'the launcher icons (see README)',
    );
  });

  // The console marks are copies too (website/web/static/consoles/CREDITS.md).
  test('the bundled console marks match the website', () {
    final upstream = Directory('../website/web/static/consoles');
    if (!upstream.existsSync()) return;
    for (final f in upstream.listSync().whereType<File>().where((f) => f.path.endsWith('.svg'))) {
      final name = f.uri.pathSegments.last;
      final ours = File('assets/consoles/$name');
      expect(ours.existsSync(), isTrue, reason: 'assets/consoles/$name is missing');
      expect(ours.readAsBytesSync(), equals(f.readAsBytesSync()),
          reason: '$name has changed on the website; cp ../website/web/static/consoles/*.svg assets/consoles/');
    }
  });

  test('the launcher icons exist at every density', () {
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
        File('android/app/src/main/res/mipmap-$d/ic_launcher.png').existsSync(),
        isTrue,
        reason: 'mipmap-$d/ic_launcher.png is missing',
      );
    }
  });
}

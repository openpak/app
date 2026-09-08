import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // This app shipped once without it. Flutter's template declares INTERNET only
  // in the debug and profile manifests, where it serves hot reload, so a debug
  // build works, every test passes, and the release APK cannot open a socket —
  // which reaches a person as "could not reach OpenPak", indistinguishable from
  // their wifi being off.
  test('the release manifest grants INTERNET', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest.contains('android.permission.INTERNET'),
      isTrue,
      reason: 'release builds cannot reach the network without it',
    );
  });
}

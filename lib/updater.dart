/// Update check: on start, once per session, ask GitHub for the latest release
/// of openpak/app and, when it is newer than this build, offer to install it.
///
/// Why GitHub releases: they are the only place the app is distributed (signed
/// Android APKs, `vX.Y.Z` tags, .github/workflows/release.yml), the repo is
/// public, and the API reports each asset's size and SHA-256 digest, so no
/// OpenPak-hosted manifest is needed. There is no desktop or store build to
/// serve; anywhere that cannot install an APK opens the release page instead.
///
/// Nothing here may disturb the app: every failure is a log line.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'crash_reports.dart' show appVersion;
import 'l10n.dart';

const releasesApi = 'https://api.github.com/repos/openpak/app/releases/latest';

/// For testing the updater from the current build: `--dart-define=
/// UPDATE_CURRENT_VERSION=0.1.0` makes the app believe it is that old.
const _versionOverride = String.fromEnvironment('UPDATE_CURRENT_VERSION');
String get runningVersion =>
    _versionOverride.isEmpty ? appVersion : _versionOverride;

/// A release version, `1.2.3` with an optional leading `v` and a `+build` or
/// `-pre` tail that is ignored for ordering.
class Version implements Comparable<Version> {
  Version(this.parts);

  /// Null for anything that is not `N.N.N`-shaped.
  static Version? parse(String text) {
    final m = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:[+-].*)?$',
    ).firstMatch(text.trim());
    if (m == null) return null;
    return Version([for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)]);
  }

  final List<int> parts;

  @override
  int compareTo(Version other) {
    for (var i = 0; i < 3; i++) {
      final c = parts[i].compareTo(other.parts[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  bool operator >(Version other) => compareTo(other) > 0;

  @override
  String toString() => parts.join('.');
}

/// One downloadable file of a release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });
  final String name;
  final String url;
  final int size;

  /// Lower-case hex, from GitHub's `sha256:` digest; null when it has none.
  final String? sha256;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.assets,
  });

  /// Null when the response is not a usable release (no version, a draft or a
  /// pre-release); the check then says nothing.
  static ReleaseInfo? fromJson(Object? json) {
    if (json is! Map || json['draft'] == true || json['prerelease'] == true) {
      return null;
    }
    final version = Version.parse('${json['tag_name']}');
    final page = json['html_url'];
    if (version == null || page is! String) return null;
    final assets = <ReleaseAsset>[];
    for (final a in (json['assets'] as List? ?? const [])) {
      if (a is! Map ||
          a['name'] is! String ||
          a['browser_download_url'] is! String) {
        continue;
      }
      final digest = a['digest'];
      assets.add(
        ReleaseAsset(
          name: a['name'] as String,
          url: a['browser_download_url'] as String,
          size: a['size'] is int ? a['size'] as int : 0,
          sha256: digest is String && digest.startsWith('sha256:')
              ? digest.substring(7).toLowerCase()
              : null,
        ),
      );
    }
    return ReleaseInfo(
      version: version,
      notes: shortNotes('${json['body'] ?? ''}'),
      pageUrl: page,
      assets: assets,
    );
  }

  final Version version;
  final String notes;
  final String pageUrl;
  final List<ReleaseAsset> assets;

  /// The APK for a device whose ABIs are listed best first; null when the
  /// release has none for it (the page is opened instead).
  ReleaseAsset? apkFor(List<String> abis) {
    for (final abi in abis) {
      for (final a in assets) {
        if (a.name == 'app-$abi-release.apk') return a;
      }
    }
    return null;
  }
}

/// Release notes for a dialog: plain lines, no markdown marks, cut short.
String shortNotes(String body, {int max = 500}) {
  final lines = [
    for (final raw in body.split('\n'))
      raw
          .replaceAll(RegExp(r'[*`#]'), '')
          .replaceFirst(RegExp(r'^\s*[-+]\s+'), '- ')
          .trim(),
  ].where((l) => l.isNotEmpty);
  final text = lines.join('\n');
  return text.length <= max ? text : '${text.substring(0, max).trimRight()}…';
}

/// The once-per-session logic. One instance lives as long as the app does, so
/// "Later" is remembered in memory only: the next start asks again.
class UpdateChecker {
  UpdateChecker({http.Client? client, String? current})
    : _client = client ?? http.Client(),
      current = Version.parse(current ?? runningVersion);

  final http.Client _client;
  final Version? current;
  bool _checked = false;
  final _later = <String>{};

  /// The release to offer, or null: already checked this session, nothing
  /// newer, "Later" was chosen for it, or the network failed.
  Future<ReleaseInfo?> check() async {
    if (_checked || current == null) return null;
    _checked = true;
    try {
      final r = await _client
          .get(
            Uri.parse(releasesApi),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) {
        debugPrint('update check: HTTP ${r.statusCode}');
        return null;
      }
      final release = ReleaseInfo.fromJson(
        jsonDecode(utf8.decode(r.bodyBytes)),
      );
      return release != null && shouldOffer(release) ? release : null;
    } catch (e) {
      debugPrint('update check failed: $e');
      return null;
    }
  }

  bool shouldOffer(ReleaseInfo release) {
    final now = current;
    return now != null &&
        release.version > now &&
        !_later.contains('${release.version}');
  }

  /// "Later": do not offer this version again until the next start.
  void later(ReleaseInfo release) => _later.add('${release.version}');
}

class UpdateFailure implements Exception {
  UpdateFailure(this.reason);
  final String reason;
  @override
  String toString() => 'UpdateFailure($reason)';
}

class _DigestSink implements Sink<Digest> {
  late Digest digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

/// Streams [asset] into [file] and refuses it unless the size and, when the
/// release publishes one, the SHA-256 match. A bad file is deleted.
Future<void> downloadVerified(
  http.Client client,
  ReleaseAsset asset,
  File file, {
  void Function(double fraction)? onProgress,
}) async {
  final response = await client.send(http.Request('GET', Uri.parse(asset.url)));
  if (response.statusCode != 200) {
    throw UpdateFailure('HTTP ${response.statusCode}');
  }
  final total = asset.size > 0 ? asset.size : (response.contentLength ?? 0);
  final sink = file.openWrite();
  final hash = _DigestSink();
  final input = sha256.startChunkedConversion(hash);
  var got = 0;
  try {
    await for (final chunk in response.stream) {
      sink.add(chunk);
      input.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress?.call(got / total);
    }
    input.close();
    await sink.close();
  } catch (_) {
    await sink.close().catchError((_) {});
    if (file.existsSync()) file.deleteSync();
    rethrow;
  }
  final digest = hash.digest.toString();
  if ((asset.size > 0 && got != asset.size) ||
      (asset.sha256 != null && digest != asset.sha256)) {
    file.deleteSync();
    throw UpdateFailure('size or checksum mismatch');
  }
}

const _channel = MethodChannel('org.openpak/update');

/// Offers [release] in a dialog and acts on the answer. [checker] hears about
/// "Later". Never throws.
Future<void> offerUpdate(
  BuildContext context,
  UpdateChecker checker,
  ReleaseInfo release,
) async {
  try {
    final l = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.updateTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.updateBody(release.version.toString(), runningVersion)),
              if (release.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(release.notes),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.updateLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.updateNow),
          ),
        ],
      ),
    );
    if (yes != true) return checker.later(release);
    if (!context.mounted) return;
    await _update(context, release);
  } catch (e) {
    debugPrint('update failed: $e');
  }
}

Future<void> _update(BuildContext context, ReleaseInfo release) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));
  Future<void> openPage() async {
    if (!await launchUrl(
      Uri.parse(release.pageUrl),
      mode: LaunchMode.externalApplication,
    )) {
      say(l.updateFailed);
    }
  }

  // Only Android can install an APK; elsewhere (and when the release has none
  // for this phone) the release page is the update.
  final asset = Platform.isAndroid ? release.apkFor(await _abis()) : null;
  if (asset == null) return openPage();
  if (!await _channel
      .invokeMethod<bool>('canInstall')
      .then((v) => v ?? false)) {
    await _channel.invokeMethod('allowInstall');
    say(l.updateAllowInstall);
    return;
  }
  if (!context.mounted) return;
  final progress = ValueNotifier<double?>(null);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l.updateDownloading),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, value, _) => LinearProgressIndicator(value: value),
          ),
        ),
      ),
    ),
  );
  final client = http.Client();
  try {
    final dir = Directory(await _channel.invokeMethod<String>('dir') ?? '');
    for (final old in dir.listSync()) {
      old.deleteSync(recursive: true);
    }
    final file = File('${dir.path}/${asset.name}');
    await downloadVerified(
      client,
      asset,
      file,
      onProgress: (f) => progress.value = f,
    );
    navigator.pop();
    await _channel.invokeMethod('install', file.path);
  } catch (e) {
    debugPrint('update download failed: $e');
    navigator.pop();
    say(l.updateFailed);
  } finally {
    client.close();
    progress.dispose();
  }
}

/// The phone's ABIs, best first, e.g. `[arm64-v8a, armeabi-v7a]`.
Future<List<String>> _abis() async {
  try {
    final r = await Process.run('getprop', ['ro.product.cpu.abilist']);
    return (r.stdout as String)
        .trim()
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

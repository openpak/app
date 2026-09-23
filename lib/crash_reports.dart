/// Crash reports: an unhandled error is written down on the phone, and only
/// sent to openpak.org (`POST /api/v1/crash-reports`) once the person says so.
///
/// Nothing leaves the phone without consent. A report waits in a small queue
/// (the last [CrashQueue.capacity]) in the same keystore as the sign-in, so a
/// crash that took the app down is offered on the next launch. The answer can
/// be remembered: "Always send" sends new reports without asking, "Never send"
/// throws them away without asking.
///
/// No new dependency: the version is a constant (a test keeps it equal to
/// pubspec.yaml), and the Android version and model come from `getprop`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'l10n.dart';
import 'widgets.dart';

/// The app's version, as in pubspec.yaml (without the build number).
/// test/crash_reports_test.dart fails when the two differ.
const appVersion = '0.11.1';

/// One error, as saved on the phone.
class CrashReport {
  CrashReport({
    required this.message,
    this.stack = '',
    this.errorCode,
    this.errorType,
    this.context,
    DateTime? time,
  }) : time = (time ?? DateTime.now()).toUtc();

  /// A stack trace is kept up to this many characters: enough to find the
  /// crash, small enough that five of them fit in the keystore.
  static const maxStack = 16 * 1024;
  static const maxMessage = 2 * 1024;

  factory CrashReport.from(Object error, StackTrace? stack, {String? context}) => CrashReport(
    message: _cut(error.toString(), maxMessage),
    stack: _cut(stack?.toString() ?? '', maxStack),
    errorCode: error is ApiException ? (error.code ?? 'http_${error.statusCode}') : null,
    errorType: error.runtimeType.toString(),
    context: context,
  );

  final String message;
  final String stack;
  final String? errorCode;
  final String? errorType;
  final String? context;
  final DateTime time;

  /// The same error again (a broken widget rebuilt every frame) is one report.
  bool sameAs(CrashReport o) => message == o.message && stackTop(stack) == stackTop(o.stack);

  Map<String, dynamic> toJson() => {
    'message': message,
    'stack': stack,
    'error_code': ?errorCode,
    'error_type': ?errorType,
    'context': ?context,
    'time': time.toIso8601String(),
  };

  factory CrashReport.fromJson(Map<String, dynamic> j) => CrashReport(
    message: j['message'] as String? ?? '',
    stack: j['stack'] as String? ?? '',
    errorCode: j['error_code'] as String?,
    errorType: j['error_type'] as String?,
    context: j['context'] as String?,
    time: DateTime.tryParse(j['time'] as String? ?? ''),
  );

  /// The text file sent as `attachment`: the whole saved report.
  String attachmentText({required String version, required String os}) => [
    'OpenPak app $version on $os',
    'Time: ${time.toIso8601String()}',
    if (errorType != null) 'Type: $errorType',
    if (context != null) 'Context: $context',
    '',
    message,
    '',
    stack,
  ].join('\n');
}

String _cut(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// The first few frames of a stack trace, for the report's summary fields.
String stackTop(String stack, {int lines = 5}) => _cut(
  stack.split('\n').where((l) => l.trim().isNotEmpty).take(lines).join('\n'),
  1000,
);

/// The phone as a report names it: "Android 15" or "iOS 18.0", and the model
/// where the platform tells it without a plugin.
class DeviceInfo {
  const DeviceInfo({required this.os, this.fields = const {}});
  final String os;
  final Map<String, String> fields;

  static Future<DeviceInfo> read() async {
    try {
      if (Platform.isAndroid) {
        Future<String> prop(String name) async {
          final r = await Process.run('getprop', [name]);
          return (r.stdout as String).trim();
        }

        final release = await prop('ro.build.version.release');
        final sdk = await prop('ro.build.version.sdk');
        final maker = await prop('ro.product.manufacturer');
        final model = await prop('ro.product.model');
        return DeviceInfo(
          os: osName('android', release.isEmpty ? Platform.operatingSystemVersion : release),
          fields: {
            if (sdk.isNotEmpty) 'sdk': sdk,
            if (model.isNotEmpty) 'model': maker.isEmpty ? model : '$maker $model',
          },
        );
      }
      return DeviceInfo(os: osName(Platform.operatingSystem, Platform.operatingSystemVersion));
    } catch (_) {
      return DeviceInfo(os: Platform.operatingSystem);
    }
  }
}

/// "android" + "15" -> "Android 15"; "ios" + "Version 18.0 (Build 22A3354)"
/// -> "iOS 18.0". Anything else is kept as it came.
String osName(String os, String version) {
  final name = switch (os) {
    'android' => 'Android',
    'ios' => 'iOS',
    'macos' => 'macOS',
    'linux' => 'Linux',
    'windows' => 'Windows',
    _ => os,
  };
  final number = RegExp(r'\d+(\.\d+)*').firstMatch(version)?.group(0);
  if (os == 'android' || os == 'ios') return '$name ${number ?? version}'.trim();
  return '$name $version'.trim();
}

/// The `meta` part of `POST /crash-reports`.
Map<String, dynamic> crashMeta(
  CrashReport r, {
  required String version,
  required DeviceInfo device,
  String? locale,
}) => {
  'source': 'app',
  'version': version,
  'os': device.os,
  'error_code': ?r.errorCode,
  'message': r.message,
  'fields': <String, String>{
    ...device.fields,
    'time': r.time.toIso8601String(),
    'error_type': ?r.errorType,
    'context': ?r.context,
    'locale': ?locale,
    if (r.stack.isNotEmpty) 'stack_top': stackTop(r.stack),
  },
};

/// What the person chose to do with reports from now on.
enum CrashConsent { ask, always, never }

/// Where reports and the remembered answer live: the keystore the sign-in
/// already uses, so no second storage plugin.
class CrashStore {
  CrashStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;
  static const _queueKey = 'openpak.crash.queue';
  static const _consentKey = 'openpak.crash.consent';

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {
      // A keystore that will not open loses the report; it must not crash the
      // crash handler.
    }
  }

  Future<String?> readQueue() => _read(_queueKey);
  Future<void> writeQueue(String? json) => _write(_queueKey, json);

  Future<CrashConsent> consent() async =>
      CrashConsent.values.asNameMap()[await _read(_consentKey)] ?? CrashConsent.ask;
  Future<void> setConsent(CrashConsent c) => _write(_consentKey, c == CrashConsent.ask ? null : c.name);
}

/// The saved reports, oldest first, at most [capacity] of them.
class CrashQueue {
  CrashQueue([List<CrashReport>? reports]) : reports = reports ?? [];

  static const capacity = 5;
  final List<CrashReport> reports;

  /// Adds [r] unless the same error is already waiting; the oldest goes when
  /// the queue is full. False when nothing was added.
  bool add(CrashReport r) {
    if (reports.any((o) => o.sameAs(r))) return false;
    reports.add(r);
    while (reports.length > capacity) {
      reports.removeAt(0);
    }
    return true;
  }

  String encode() => jsonEncode(reports.map((r) => r.toJson()).toList());

  /// A queue that will not parse (an older app, a half write) is empty.
  static CrashQueue decode(String? s) {
    if (s == null || s.isEmpty) return CrashQueue();
    try {
      return CrashQueue([
        for (final e in jsonDecode(s) as List) CrashReport.fromJson(e as Map<String, dynamic>),
      ]);
    } catch (_) {
      return CrashQueue();
    }
  }
}

/// Catches unhandled errors, keeps them, and sends them when allowed.
class CrashReporter {
  CrashReporter({CrashStore? store, this.version = appVersion}) : store = store ?? CrashStore();

  final CrashStore store;
  final String version;
  DeviceInfo device = DeviceInfo(os: Platform.operatingSystem);

  /// The app's language, sent as a field.
  String? locale;

  /// Called after a new report is saved, so the app can offer it right away.
  void Function()? onReport;

  Future<void> _lock = Future.value();

  /// Serialises the read-modify-write of the queue: two errors in one frame
  /// must not overwrite each other.
  Future<T> _locked<T>(Future<T> Function() f) {
    final result = _lock.then((_) => f());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Hooks the framework's error handlers. Errors are still printed as
  /// before; they are also saved.
  void install() {
    unawaited(DeviceInfo.read().then((d) => device = d));
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
      unawaited(record(details.exception, details.stack, context: details.context?.toDescription()));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Unhandled error: $error\n$stack');
      unawaited(record(error, stack));
      return true;
    };
  }

  /// Saves one error. Never throws.
  Future<void> record(Object error, StackTrace? stack, {String? context}) async {
    try {
      final added = await _locked(() async {
        if (await store.consent() == CrashConsent.never) return false;
        final q = CrashQueue.decode(await store.readQueue());
        final added = q.add(CrashReport.from(error, stack, context: context));
        if (added) await store.writeQueue(q.encode());
        return added;
      });
      if (added) onReport?.call();
    } catch (_) {}
  }

  Future<List<CrashReport>> pending() async =>
      _locked(() async => CrashQueue.decode(await store.readQueue()).reports);

  Future<void> _drop(Iterable<CrashReport> gone) => _locked(() async {
    final q = CrashQueue.decode(await store.readQueue());
    q.reports.removeWhere((r) => gone.any((g) => g.sameAs(r) && g.time == r.time));
    await store.writeQueue(q.reports.isEmpty ? null : q.encode());
  });

  /// Throws the waiting reports away.
  Future<void> discard(List<CrashReport> reports) => _drop(reports);

  /// Sends [reports] (the person agreed); each one sent leaves the queue, a
  /// failed one stays and is offered again. Returns how many were sent.
  Future<int> send(OpenPakApi api, List<CrashReport> reports) async {
    final sent = <CrashReport>[];
    for (final r in reports) {
      try {
        await api.sendCrashReport(
          crashMeta(r, version: version, device: device, locale: locale),
          attachment: r.attachmentText(version: version, os: device.os),
        );
        sent.add(r);
      } catch (_) {
        // Offline or a server that is down: keep it for the next launch.
      }
    }
    if (sent.isNotEmpty) await _drop(sent);
    return sent.length;
  }
}

/// Asks whether to send the waiting reports, unless an earlier answer was
/// remembered. "Don't send" throws them away; a report that fails to send
/// stays and is asked about again next time.
Future<void> offerCrashReports(BuildContext context, CrashReporter reporter, OpenPakApi api) async {
  final waiting = await reporter.pending();
  if (waiting.isEmpty) return;
  final consent = await reporter.store.consent();
  if (consent == CrashConsent.never) return reporter.discard(waiting);
  final asked = consent == CrashConsent.ask;
  if (asked) {
    if (!context.mounted) return;
    final l = context.l10n;
    final answer = await showDialog<CrashConsent>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l.crashTitle),
        content: Text(l.crashBody(waiting.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, CrashConsent.never),
            child: Text(l.crashNever),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.crashDontSend),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, CrashConsent.always),
            child: Text(l.crashAlways),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, CrashConsent.ask),
            child: Text(l.crashSend),
          ),
        ],
      ),
    );
    if (answer == null) return reporter.discard(waiting);
    if (answer != CrashConsent.ask) await reporter.store.setConsent(answer);
    if (answer == CrashConsent.never) return reporter.discard(waiting);
  }
  final sent = await reporter.send(api, waiting);
  // Remembered "Always send" sends quietly; an answer just given is thanked.
  if (!context.mounted) return;
  final l = context.l10n;
  if (sent < waiting.length) {
    showToast(context, l.crashSendFailed);
  } else if (asked) {
    showToast(context, l.crashSent);
  }
}

/// The remembered answer, on the account page: ask, always or never.
class CrashConsentTile extends StatefulWidget {
  const CrashConsentTile({super.key, required this.store});
  final CrashStore store;

  @override
  State<CrashConsentTile> createState() => _CrashConsentTileState();
}

class _CrashConsentTileState extends State<CrashConsentTile> {
  CrashConsent? _value;

  @override
  void initState() {
    super.initState();
    widget.store.consent().then((c) {
      if (mounted) setState(() => _value = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListTile(
      leading: const Icon(Icons.bug_report_outlined),
      title: Text(l.crashSettingTitle),
      trailing: _value == null
          ? null
          : DropdownButton<CrashConsent>(
              value: _value,
              underline: const SizedBox.shrink(),
              onChanged: (c) async {
                if (c == null) return;
                setState(() => _value = c);
                await widget.store.setConsent(c);
              },
              items: [
                DropdownMenuItem(value: CrashConsent.ask, child: Text(l.crashSettingAsk)),
                DropdownMenuItem(value: CrashConsent.always, child: Text(l.crashAlways)),
                DropdownMenuItem(value: CrashConsent.never, child: Text(l.crashNever)),
              ],
            ),
    );
  }
}

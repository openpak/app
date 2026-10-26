import 'package:flutter/material.dart';

import 'api.dart';
import 'crash_reports.dart';
import 'l10n.dart';
import 'pakka.dart';
import 'shell.dart';
import 'theme.dart';
import 'session.dart';
import 'sign_in_page.dart';

/// The server this build talks to. Override for a local stack with
/// `--dart-define=OPENPAK_BASE_URL=http://10.0.2.2:20010`.
const baseUrl = String.fromEnvironment(
  'OPENPAK_BASE_URL',
  defaultValue: 'https://openpak.org',
);

/// The Pakka harness this build diagnoses against. Empty until Pakka has a
/// public endpoint; without it the app shows no diagnostics entry. Point a
/// dev build at a local harness with
/// `--dart-define=PAKKA_BASE_URL=http://10.0.2.2:24800`.
const pakkaBaseUrl = String.fromEnvironment('PAKKA_BASE_URL', defaultValue: '');

/// Unhandled errors are saved from the first frame on; nothing is sent
/// until the person agrees (see crash_reports.dart).
final crashReporter = CrashReporter();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  crashReporter.install();
  runApp(const OpenPakApp());
}

class OpenPakApp extends StatefulWidget {
  const OpenPakApp({super.key});
  @override
  State<OpenPakApp> createState() => _OpenPakAppState();
}

class _OpenPakAppState extends State<OpenPakApp> {
  final _session = Session();
  final _api = OpenPakApi(baseUrl: baseUrl);

  /// Null until Pakka is served somewhere this build can reach: no endpoint,
  /// no diagnostics entry, rather than a button that cannot work.
  final _pakka = pakkaBaseUrl.isEmpty ? null : PakkaApi(baseUrl: pakkaBaseUrl);
  final _navigator = GlobalKey<NavigatorState>();
  bool _restoring = true;
  bool _offering = false;

  @override
  void initState() {
    super.initState();
    // The claim below is only true because of this line: the client raises it
    // once, from wherever the 401 came from, and the whole app returns to the
    // sign-in form instead of every tab failing to load forever.
    _api.onUnauthorized = () {
      _session.clear();
      if (mounted) setState(() {});
    };
    // A report saved while the app runs is offered right away; one saved
    // before a crash took the app down, on the next launch (after _restore).
    crashReporter.onReport = _offerCrashReports;
    _restore();
  }

  /// One dialog at a time; whatever arrives meanwhile is in the queue and is
  /// offered by the next call.
  Future<void> _offerCrashReports() async {
    final context = _navigator.currentContext;
    if (_offering || context == null) return;
    _offering = true;
    try {
      await offerCrashReports(context, crashReporter, _api);
    } catch (_) {
      // The crash prompt must never become a crash of its own.
    } finally {
      _offering = false;
    }
  }

  /// A stored token means signed in until the server says otherwise; the first
  /// 401 from any screen signs out. Nothing is validated up front, because
  /// that would put a network round trip in front of the first frame.
  Future<void> _restore() async {
    _api.token = await _session.read();
    if (mounted) setState(() => _restoring = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerCrashReports());
  }

  Future<void> _onSignedIn(String token) async {
    await _session.write(token);
    setState(() {});
  }

  Future<void> _onSignedOut() async {
    await _api.signOut();
    await _session.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'OpenPak',
      // The website's tokens, so the two are visibly one product.
      theme: openPakLight(),
      darkTheme: openPakDark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // The language the app settled on goes with every call, so the account
      // e-mails the website sends read in it too.
      builder: (context, child) {
        _api.language = Localizations.localeOf(context).toLanguageTag();
        _pakka?.language = _api.language;
        crashReporter.locale = _api.language;
        return child!;
      },
      home: _restoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _api.token == null
          ? SignInPage(api: _api, onSignedIn: _onSignedIn)
          : Shell(api: _api, onSignedOut: _onSignedOut, pakka: _pakka),
    );
  }
}

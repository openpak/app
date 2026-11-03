import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'crash_reports.dart';
import 'l10n.dart';
import 'rewards_theme.dart';
import 'shell.dart';
import 'updater.dart';
import 'session.dart';
import 'sign_in_page.dart';

/// The server this build talks to. Override for a local stack with
/// `--dart-define=OPENPAK_BASE_URL=http://10.0.2.2:20010`.
const baseUrl = String.fromEnvironment(
  'OPENPAK_BASE_URL',
  defaultValue: 'https://openpak.org',
);

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
  final _navigator = GlobalKey<NavigatorState>();
  final _updates = UpdateChecker();
  late final _themes = RewardsThemeController(_api, navigatorKey: _navigator);
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
      _themes.clear();
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
    // The equipped theme arrives when it arrives; the first frame never waits.
    if (_api.token != null) unawaited(_themes.load());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _offerCrashReports();
      await _offerUpdate();
    });
  }

  /// Once per app session (the checker refuses a second call): a newer release
  /// is offered after any crash prompt. Failures are silent.
  Future<void> _offerUpdate() async {
    try {
      final release = await _updates.check();
      final context = _navigator.currentContext;
      if (release == null || context == null || !context.mounted) return;
      await offerUpdate(context, _updates, release);
    } catch (_) {}
  }

  Future<void> _onSignedIn(String token) async {
    await _session.write(token);
    setState(() {});
    unawaited(_themes.load());
  }

  Future<void> _onSignedOut() async {
    await _api.signOut();
    await _session.clear();
    _themes.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RewardsThemeScope(
      controller: _themes,
      child: ListenableBuilder(
        listenable: _themes,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigator,
          title: 'OpenPak',
          // The website's tokens, so the two are visibly one product; an
          // equipped (or previewed) Rewards theme re-colours all of it.
          theme: _themes.light,
          darkTheme: _themes.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The language the app settled on goes with every call, so the account
          // e-mails the website sends read in it too.
          builder: (context, child) {
            _api.language = Localizations.localeOf(context).toLanguageTag();
            crashReporter.locale = _api.language;
            // The preview bar lives here so it is on every page, pushed ones too.
            return ThemePreviewHost(controller: _themes, child: child!);
          },
          home: _restoring
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : _api.token == null
              ? SignInPage(api: _api, onSignedIn: _onSignedIn)
              : Shell(api: _api, onSignedOut: _onSignedOut),
        ),
      ),
    );
  }
}

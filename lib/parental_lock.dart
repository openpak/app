/// The lock in front of the parental screens: the phone's own unlock
/// (biometrics, falling back to its PIN, pattern or passcode), never a PIN of
/// the app's. Opening the screens asks, and so does coming back to them after
/// more than [ParentalLock.relockAfter] in the background.
///
/// The gate is also where the screens are kept out of screenshots and the
/// recent-apps picture: [secureScreens] is on for as long as it is mounted.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

enum LockOutcome {
  allowed,

  /// Cancelled, failed, or refused for now (a lockout). Closed, never open.
  denied,

  /// The phone can ask but has no screen lock set. Not the password path:
  /// otherwise removing the screen lock would be a way around it.
  noLockScreen,

  /// The platform has no device authentication at all, so the account
  /// password stands in for it.
  password,
}

/// The decisions, apart from any widget so a test can drive them.
class ParentalLock {
  ParentalLock({LocalAuthentication? auth, TargetPlatform? platform, DateTime Function()? now})
    : _auth = auth ?? LocalAuthentication(),
      platform = platform ?? defaultTargetPlatform,
      now = now ?? DateTime.now;

  final LocalAuthentication _auth;
  final TargetPlatform platform;
  final DateTime Function() now;

  static const relockAfter = Duration(seconds: 60);

  /// Android and iOS always have a device lock to ask, whether or not the
  /// phone has one set; the app ships nowhere else.
  bool get deviceAuth => platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  Future<LockOutcome> unlock(String reason) async {
    if (!deviceAuth) return LockOutcome.password;
    try {
      // False on Android and iOS means no screen lock and no biometrics.
      if (!await _auth.isDeviceSupported()) return LockOutcome.noLockScreen;
      return await _auth.authenticate(localizedReason: reason) ? LockOutcome.allowed : LockOutcome.denied;
    } on LocalAuthException catch (e) {
      return e.code == LocalAuthExceptionCode.noCredentialsSet ? LockOutcome.noLockScreen : LockOutcome.denied;
    } catch (_) {
      // A plugin that failed to answer leaves the screens shut.
      return LockOutcome.denied;
    }
  }

  /// Whether time away since [hiddenAt] asks for the unlock again.
  bool expired(DateTime? hiddenAt) => hiddenAt != null && now().difference(hiddenAt) > relockAfter;
}

/// The phone's unlock, or the account password where it has none of its own
/// to ask. The gate asks it on the way in; changing a PIN asks it again.
Future<LockOutcome> askParentalUnlock(BuildContext context, OpenPakApi api, ParentalLock lock, String reason) async {
  final outcome = await lock.unlock(reason);
  if (outcome != LockOutcome.password || !context.mounted) return outcome;
  return _password(context, api);
}

/// The account password, sent once and not kept: the dialog's field goes
/// with the dialog.
Future<LockOutcome> _password(BuildContext context, OpenPakApi api) async {
  final l = context.l10n;
  final typed = await promptForm(
    context,
    title: l.parentalTitle,
    labels: ['*${l.commonPassword}'],
    action: l.parentalUnlock,
    help: l.parentalPasswordLock,
  );
  if (typed == null || typed.first.isEmpty) return LockOutcome.denied;
  try {
    await api.parentalUnlock(typed.first);
    return LockOutcome.allowed;
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, apiErrorText(l, e));
    return LockOutcome.denied;
  }
}

/// Android's FLAG_SECURE (no screenshots, a blank recent-apps picture) and,
/// on iOS, a cover over the window whenever the app is not active. Set in
/// MainActivity.kt and AppDelegate.swift; elsewhere there is nothing to set.
Future<void> secureScreens(bool on) async {
  try {
    await const MethodChannel('org.openpak/secure').invokeMethod<void>('set', on);
  } on MissingPluginException {
    // Desktop and tests: no window flag to set.
  } on PlatformException {
    // Never a reason to keep the screens shut; the unlock still stands.
  }
}

/// Shows [child] only once [lock] allows it; back from the background after
/// too long, it closes whatever parental screen is on top and asks again.
class ParentalLockGate extends StatefulWidget {
  const ParentalLockGate({super.key, required this.api, required this.child, this.lock});
  final OpenPakApi api;
  final Widget child;
  final ParentalLock? lock;

  @override
  State<ParentalLockGate> createState() => _ParentalLockGateState();
}

class _ParentalLockGateState extends State<ParentalLockGate> {
  late final ParentalLock _lock = widget.lock ?? ParentalLock();
  late final AppLifecycleListener _life;
  LockOutcome? _outcome;
  bool _asking = false;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    // The prompt itself can send the app to the background (Android's PIN
    // screen is another activity), so time away is counted only outside it.
    _life = AppLifecycleListener(
      onHide: () {
        if (!_asking) _hiddenAt ??= _lock.now();
      },
      onResume: _resumed,
    );
    secureScreens(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    _life.dispose();
    secureScreens(false);
    super.dispose();
  }

  void _resumed() {
    final away = _hiddenAt;
    _hiddenAt = null;
    if (_asking || _outcome != LockOutcome.allowed || !_lock.expired(away)) return;
    final here = ModalRoute.of(context);
    Navigator.of(context).popUntil((r) => r == here);
    setState(() => _outcome = null);
    _unlock();
  }

  Future<void> _unlock() async {
    if (_asking || !mounted) return;
    setState(() => _asking = true);
    final outcome = await askParentalUnlock(context, widget.api, _lock, context.l10n.parentalLockReason);
    if (!mounted) return;
    setState(() {
      _asking = false;
      _outcome = outcome;
      _hiddenAt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_outcome == LockOutcome.allowed) return widget.child;
    final t = tokensOf(context);
    final l = context.l10n;
    final why = switch (_outcome) {
      LockOutcome.noLockScreen => l.parentalNoScreenLock,
      _ when !_lock.deviceAuth => l.parentalPasswordLock,
      _ => l.parentalLocked,
    };
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.parentalTitle)),
      // A Builder, so the padding is read below the Scaffold: with
      // extendBodyBehindAppBar the Scaffold's MediaQuery counts the app bar in
      // its top padding, and this page's own context, above it, only the
      // status bar. Read from there, the first panel sat under the bar.
      body: Builder(
        builder: (context) => ListView(
          padding: pagePadding(context),
          children: [
            Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(why, style: TextStyle(color: t.muted)),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _asking ? null : _unlock,
              icon: const Icon(Icons.lock_open),
              label: Text(l.parentalUnlock),
            ),
          ],
        ),
      ),
    );
  }
}

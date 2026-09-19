import 'package:flutter/material.dart';

import 'account_details_page.dart';
import 'api.dart';
import 'theme.dart';
import 'two_factor_page.dart';
import 'widgets.dart';

/// Who you are, what is linked, how you sign in, and where you are signed in.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.api, required this.onSignedOut});
  final OpenPakApi api;
  final Future<void> Function() onSignedOut;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late Future<(Account, List<WebSession>)> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() {
    _data = Future.wait([widget.api.me(), widget.api.sessions()])
        .then((r) => (r[0] as Account, r[1] as List<WebSession>));
  });

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<(Account, List<WebSession>)>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final (me, sessions) = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Panel(
                  child: InkWell(
                    onTap: () => _openDetails(me),
                    child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        AccountAvatar(api: widget.api, account: me, size: 56),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                me.displayName.isEmpty ? 'You' : me.displayName,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              // The friend code exists to be handed to someone
                              // else, so it is one tap to copy.
                              if (me.friendCode != null)
                                InkWell(
                                  onTap: () => copyToClipboard(
                                    context,
                                    me.friendCode!,
                                    'Friend code',
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        me.friendCode!,
                                        style: TextStyle(color: t.ink2),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.copy_rounded,
                                        size: 15,
                                        color: t.muted,
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Text(
                                  'No friend code until a console is linked.',
                                  style: TextStyle(color: t.muted, fontSize: 13),
                                ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: t.muted),
                      ],
                    ),
                  ),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Linked'),
                Panel(
                  child: Column(
                    children: [
                      if (me.linkedPlatforms.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Nothing linked yet. Link a console from its own '
                            'settings, or a Wii or DS below.',
                            style: TextStyle(color: t.muted),
                          ),
                        ),
                      for (final ns in me.linkedPlatforms) ...[
                        ListTile(
                          leading: const Icon(Icons.videogame_asset_outlined),
                          title: Text(platformNames[ns] ?? ns),
                          trailing: TextButton(
                            onPressed: () => _unlink(ns),
                            child: Text('Unlink', style: TextStyle(color: t.bad)),
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      if (!me.linkedPlatforms.contains('wfc'))
                        ListTile(
                          leading: const Icon(Icons.add_link),
                          title: const Text('Link a Wii or DS'),
                          onTap: _linkWfc,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Security'),
                Panel(
                  child: Column(
                    children: [
                      // The address itself is not in the API; whether it is
                      // confirmed is, and that is what needs acting on.
                      ListTile(
                        leading: const Icon(Icons.mail_outline),
                        title: const Text('Email address'),
                        subtitle: Text(
                          me.emailVerified ? 'Confirmed' : 'Not confirmed',
                          style: TextStyle(color: me.emailVerified ? t.ok : t.warn),
                        ),
                        trailing: me.emailVerified
                            ? null
                            : TextButton(
                                onPressed: () => _act(
                                  widget.api.resendVerification,
                                  'If your address still needs confirming, a new link is on its way.',
                                ),
                                child: const Text('Send the link again'),
                              ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.alternate_email),
                        title: const Text('Change email'),
                        trailing: Icon(Icons.chevron_right, color: t.muted),
                        onTap: _changeEmail,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: const Text('Two-factor authentication'),
                        subtitle: Text(me.twoFactorEnabled
                            ? 'Signing in asks for a code from your authenticator app.'
                            : 'Off. Signing in on the website or the app asks for your password only.'),
                        trailing: me.twoFactorEnabled
                            ? TextButton(
                                onPressed: _disableTwoFactor,
                                child: Text('Turn off', style: TextStyle(color: t.bad)),
                              )
                            : TextButton(
                                onPressed: _setUpTwoFactor,
                                child: const Text('Set up'),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionLabel('Signed in', trailing: '${sessions.length}'),
                Panel(
                  child: Column(
                    children: [
                      for (var i = 0; i < sessions.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.devices_outlined),
                          title: Text(_when(sessions[i].createdAt)),
                          subtitle: sessions[i].expiresAt == null
                              ? null
                              : Text('Expires ${_date(sessions[i].expiresAt!)}'),
                          trailing: TextButton(
                            onPressed: () => _revoke(sessions[i]),
                            child: Text(
                              'Revoke',
                              style: TextStyle(color: t.bad),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: _changePassword,
                  icon: const Icon(Icons.password),
                  label: const Text('Change password'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: t.line),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.onSignedOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: t.bad,
                    side: BorderSide(color: t.line),
                  ),
                ),
                const SizedBox(height: 28),
                TextButton.icon(
                  onPressed: () => _deleteAccount(me),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete account'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: t.bad,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The details page reports whether anything changed, so the card behind it
  /// refreshes only when there is something new to show.
  Future<void> _openDetails(Account me) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccountDetailsPage(api: widget.api, account: me),
      ),
    );
    if (changed ?? false) _reload();
  }

  /// [errors] words a status the way the website does, where the server's own
  /// message would be terse.
  Future<void> _act(Future<void> Function() call, String done, {Map<int, String> errors = const {}}) async {
    try {
      await call();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, errors[e.statusCode] ?? e.message);
    }
    _reload();
  }

  static const _wrongPassword = 'That password is not right, so nothing was changed.';
  static const _codeHelp = 'The six digits from your authenticator app, or one of your recovery codes.';
  static const _locked = 'Too many wrong codes. Try again in 15 minutes.';

  /// The change happens on the website, when the link mailed to the new
  /// address is opened; until then the account keeps the old one.
  Future<void> _changeEmail() async {
    final v = await promptForm(
      context,
      title: 'Change email',
      labels: const ['New email address', '*Current password'],
      action: 'Change email',
      help: 'We send a link to the new address. Nothing changes until you open it.',
    );
    if (v == null || v[0].isEmpty || v[1].isEmpty) return;
    await _act(
      () => widget.api.changeEmail(v[0], v[1]),
      'If that address can be used, a confirmation link is on its way to it.',
      errors: const {
        400: 'That address cannot be used. Check it and try again.',
        403: _wrongPassword,
      },
    );
  }

  /// The consoles warning comes first, before the password is even asked for,
  /// and again on the page where two-factor is switched on.
  Future<void> _setUpTwoFactor() async {
    final v = await promptForm(
      context,
      title: 'Set up two-factor',
      labels: const ['*Current password'],
      action: 'Continue',
      help: consolesWarning,
    );
    if (v == null || v[0].isEmpty) return;
    final TwoFactorSecret secret;
    try {
      secret = await widget.api.twoFactorSetup(v[0]);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.statusCode == 403 ? _wrongPassword : e.message);
      return;
    }
    if (!mounted) return;
    final on = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TwoFactorSetupPage(api: widget.api, secret: secret)),
    );
    if ((on ?? false) && mounted) showToast(context, 'Two-factor authentication is on.');
    _reload();
  }

  Future<void> _disableTwoFactor() async {
    final v = await promptForm(
      context,
      title: 'Turn off two-factor',
      labels: const ['*Current password', 'Code'],
      action: 'Turn off',
      help: _codeHelp,
    );
    if (v == null || v[0].isEmpty || v[1].isEmpty) return;
    await _act(
      () => widget.api.twoFactorDisable(v[0], v[1]),
      'Two-factor authentication is off.',
      errors: const {
        401: 'That code is not right. Check the time on your phone and try the newest code.',
        403: _wrongPassword,
        429: _locked,
      },
    );
  }

  /// Asked twice on purpose: once to be sure, once for the password (and the
  /// code, with two-factor on) so a phone left unlocked cannot end an account.
  Future<void> _deleteAccount(Account me) async {
    if (!await confirm(
      context,
      'Delete your account?',
      detail: 'This signs you out everywhere and cannot be undone. Your friends, '
          'links and saves go with the account.',
    )) {
      return;
    }
    if (!mounted) return;
    final v = await promptForm(
      context,
      title: 'Delete account',
      labels: me.twoFactorEnabled ? const ['*Current password', 'Code'] : const ['*Current password'],
      action: 'Delete my account',
      help: '${me.twoFactorEnabled ? '$_codeHelp ' : ''}The account cannot be recovered.',
    );
    if (v == null || v.any((e) => e.isEmpty)) return;
    try {
      await widget.api.deleteAccount(v[0], code: v.length > 1 ? v[1] : null);
    } on ApiException catch (e) {
      if (mounted) {
        showToast(context, switch (e.message) {
          'wrong password' => 'That password is not right, so the account was not deleted.',
          'wrong code' => 'That code is not right, so the account was not deleted. Use a current '
              'code from your authenticator app, or a recovery code.',
          _ => e.statusCode == 429 ? _locked : e.message,
        });
      }
      return;
    }
    if (mounted) {
      showToast(context, 'Your account is being deleted and you have been signed out everywhere.');
    }
    await widget.onSignedOut();
  }

  Future<void> _unlink(String ns) async {
    final name = platformNames[ns] ?? ns;
    if (!await confirm(context, 'Unlink your $name?',
        detail: 'It stops signing in as you until it is linked again.')) {
      return;
    }
    await _act(() => widget.api.unlink(ns), '$name unlinked.');
  }

  Future<void> _linkWfc() async {
    final v = await promptForm(
      context,
      title: 'Link a Wii or DS',
      labels: const ['Friend code'],
      action: 'Link',
      help: 'Type the friend code any Wii or DS game on that console shows you. '
          'The console has no login of its own, so this is how it joins your account.',
    );
    if (v == null || v[0].isEmpty) return;
    await _act(() => widget.api.linkWfc(v[0]), 'Wii / DS linked.');
  }

  /// Every other device is signed out by the change; this one stays.
  Future<void> _changePassword() async {
    final v = await promptForm(
      context,
      title: 'Change password',
      labels: const ['*Current password', '*New password'],
      action: 'Change',
      help: 'At least 8 characters. Your other devices are signed out.',
    );
    if (v == null || v[0].isEmpty || v[1].isEmpty) return;
    await _act(() => widget.api.changePassword(v[0], v[1]), 'Password changed.');
  }

  Future<void> _revoke(WebSession s) async {
    if (!await confirm(
      context,
      'Sign that device out?',
      // Revoking the session this app is using signs the app out too, which is
      // surprising unless it is said first.
      detail: 'If it is this phone, you will be signed out here as well.',
    )) {
      return;
    }
    try {
      await widget.api.revokeSession(s.id);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
    _reload();
  }

  String _when(DateTime? d) =>
      d == null ? 'Session' : 'Signed in ${_date(d)}';

  String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }
}

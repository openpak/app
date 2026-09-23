import 'package:flutter/material.dart';

import 'account_details_page.dart';
import 'api.dart';
import 'crash_reports.dart';
import 'l10n.dart';
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
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.accountTitle)),
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
                                me.displayName.isEmpty ? l.accountYou : me.displayName,
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
                                    l.commonFriendCodeCopied,
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
                                  l.accountNoFriendCode,
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
                SectionLabel(l.accountLinked),
                Panel(
                  child: Column(
                    children: [
                      if (me.linkedPlatforms.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l.accountNothingLinked,
                            style: TextStyle(color: t.muted),
                          ),
                        ),
                      for (final ns in me.linkedPlatforms) ...[
                        ListTile(
                          leading: const Icon(Icons.videogame_asset_outlined),
                          title: Text(platformNames[ns] ?? ns),
                          trailing: TextButton(
                            onPressed: () => _unlink(ns),
                            child: Text(l.accountUnlink, style: TextStyle(color: t.bad)),
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      if (!me.linkedPlatforms.contains('wfc'))
                        ListTile(
                          leading: const Icon(Icons.add_link),
                          title: Text(l.accountLinkWfc),
                          onTap: _linkWfc,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionLabel(l.accountSecurity),
                Panel(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.mail_outline),
                        title: Text(me.email.isEmpty ? l.accountEmailAddress : me.email),
                        subtitle: Text(
                          me.emailVerified ? l.accountEmailConfirmed : l.accountEmailNotConfirmed,
                          style: TextStyle(color: me.emailVerified ? t.ok : t.warn),
                        ),
                        trailing: me.emailVerified
                            ? null
                            : TextButton(
                                onPressed: () => _act(
                                  widget.api.resendVerification,
                                  l.accountVerifySent,
                                ),
                                child: Text(l.accountVerifyResend),
                              ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.alternate_email),
                        title: Text(l.accountChangeEmail),
                        trailing: Icon(Icons.chevron_right, color: t.muted),
                        onTap: _changeEmail,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(l.twoFactorTitle),
                        subtitle: Text(me.twoFactorEnabled ? l.accountTwoFactorOn : l.accountTwoFactorOff),
                        trailing: me.twoFactorEnabled
                            ? TextButton(
                                onPressed: _disableTwoFactor,
                                child: Text(l.accountTurnOff, style: TextStyle(color: t.bad)),
                              )
                            : TextButton(
                                onPressed: _setUpTwoFactor,
                                child: Text(l.accountSetUp),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionLabel(l.accountSignedIn, trailing: '${sessions.length}'),
                Panel(
                  child: Column(
                    children: [
                      for (var i = 0; i < sessions.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.devices_outlined),
                          title: Text(_when(l, sessions[i].createdAt)),
                          subtitle: sessions[i].expiresAt == null
                              ? null
                              : Text(l.accountSessionExpires(shortDate(l, sessions[i].expiresAt!))),
                          trailing: TextButton(
                            onPressed: () => _revoke(sessions[i]),
                            child: Text(
                              l.accountRevoke,
                              style: TextStyle(color: t.bad),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Panel(child: CrashConsentTile(store: CrashStore())),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: _changePassword,
                  icon: const Icon(Icons.password),
                  label: Text(l.accountChangePassword),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: t.line),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.onSignedOut,
                  icon: const Icon(Icons.logout),
                  label: Text(l.accountSignOut),
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
                  label: Text(l.accountDelete),
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

  /// [errors] words a status the way the website does, where the generic
  /// wording of the error would be terse.
  Future<void> _act(Future<void> Function() call, String done, {Map<int, String> errors = const {}}) async {
    final l = context.l10n;
    try {
      await call();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, errors[e.statusCode] ?? apiErrorText(l, e));
    }
    _reload();
  }

  /// The change happens on the website, when the link mailed to the new
  /// address is opened; until then the account keeps the old one.
  Future<void> _changeEmail() async {
    final l = context.l10n;
    final v = await promptForm(
      context,
      title: l.accountChangeEmail,
      labels: ['@${l.accountNewEmail}', '*${l.commonCurrentPassword}'],
      action: l.accountChangeEmail,
      help: l.accountChangeEmailHelp,
    );
    if (v == null || v[0].isEmpty || v[1].isEmpty) return;
    await _act(
      () => widget.api.changeEmail(v[0], v[1]),
      l.accountChangeEmailSent,
      errors: {400: l.accountEmailInvalid, 403: l.accountWrongPassword},
    );
  }

  /// The consoles warning comes first, before the password is even asked for,
  /// and again on the page where two-factor is switched on.
  Future<void> _setUpTwoFactor() async {
    final l = context.l10n;
    final v = await promptForm(
      context,
      title: l.accountSetUpTwoFactor,
      labels: ['*${l.commonCurrentPassword}'],
      action: l.commonContinue,
      help: l.twoFactorConsolesWarning,
    );
    if (v == null || v[0].isEmpty) return;
    final TwoFactorSecret secret;
    try {
      secret = await widget.api.twoFactorSetup(v[0]);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.statusCode == 403 ? l.accountWrongPassword : apiErrorText(l, e));
      return;
    }
    if (!mounted) return;
    final on = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TwoFactorSetupPage(api: widget.api, secret: secret)),
    );
    if ((on ?? false) && mounted) showToast(context, l.twoFactorIsOn);
    _reload();
  }

  Future<void> _disableTwoFactor() async {
    final l = context.l10n;
    final v = await promptForm(
      context,
      title: l.accountTurnOffTwoFactor,
      labels: ['*${l.commonCurrentPassword}', l.commonCode],
      action: l.accountTurnOff,
      help: l.commonCodeHelp,
    );
    if (v == null || v[0].isEmpty || v[1].isEmpty) return;
    await _act(
      () => widget.api.twoFactorDisable(v[0], v[1]),
      l.twoFactorIsOff,
      errors: {401: l.errorWrongCode, 403: l.accountWrongPassword, 429: l.errorTwoFactorLocked},
    );
  }

  /// Asked twice on purpose: once to be sure, once for the password (and the
  /// code, with two-factor on) so a phone left unlocked cannot end an account.
  Future<void> _deleteAccount(Account me) async {
    final l = context.l10n;
    if (!await confirm(context, l.accountDeleteConfirm, detail: l.accountDeleteDetail)) {
      return;
    }
    if (!mounted) return;
    final v = await promptForm(
      context,
      title: l.accountDelete,
      labels: ['*${l.commonCurrentPassword}', if (me.twoFactorEnabled) l.commonCode],
      action: l.accountDeleteAction,
      help: '${me.twoFactorEnabled ? '${l.commonCodeHelp} ' : ''}${l.accountDeleteHelp}',
    );
    if (v == null || v.any((e) => e.isEmpty)) return;
    try {
      await widget.api.deleteAccount(v[0], code: v.length > 1 ? v[1] : null);
    } on ApiException catch (e) {
      if (mounted) {
        // By code, or by the English message from a server older than codes.
        showToast(context, switch (e.code ?? e.message) {
          'wrong_password' || 'wrong password' => l.accountDeleteWrongPassword,
          'wrong_code' || 'wrong code' => l.accountDeleteWrongCode,
          _ => e.statusCode == 429 ? l.errorTwoFactorLocked : apiErrorText(l, e),
        });
      }
      return;
    }
    if (mounted) {
      showToast(context, l.accountDeleted);
    }
    await widget.onSignedOut();
  }

  Future<void> _unlink(String ns) async {
    final l = context.l10n;
    final name = platformNames[ns] ?? ns;
    if (!await confirm(context, l.accountUnlinkConfirm(name), detail: l.accountUnlinkDetail)) {
      return;
    }
    await _act(() => widget.api.unlink(ns), l.accountUnlinked(name));
  }

  Future<void> _linkWfc() async {
    final l = context.l10n;
    final v = await promptForm(
      context,
      title: l.accountLinkWfc,
      labels: [l.commonFriendCode],
      action: l.accountLink,
      help: l.accountLinkWfcHelp,
    );
    if (v == null || v[0].isEmpty) return;
    await _act(() => widget.api.linkWfc(v[0]), l.accountWfcLinked);
  }

  /// Every other device is signed out by the change; this one stays.
  Future<void> _changePassword() async {
    final l = context.l10n;
    final v = await promptForm(
      context,
      title: l.accountChangePassword,
      labels: ['*${l.commonCurrentPassword}', '*${l.accountNewPassword}'],
      action: l.accountChange,
      help: l.accountChangePasswordHelp,
    );
    if (v == null || v[0].isEmpty || v[1].isEmpty) return;
    await _act(() => widget.api.changePassword(v[0], v[1]), l.accountPasswordChanged);
  }

  Future<void> _revoke(WebSession s) async {
    final l = context.l10n;
    if (!await confirm(
      context,
      l.accountRevokeConfirm,
      // Revoking the session this app is using signs the app out too, which is
      // surprising unless it is said first.
      detail: l.accountRevokeDetail,
    )) {
      return;
    }
    try {
      await widget.api.revokeSession(s.id);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    }
    _reload();
  }

  String _when(AppLocalizations l, DateTime? d) =>
      d == null ? l.accountSession : l.accountSignedInOn(shortDate(l, d));
}

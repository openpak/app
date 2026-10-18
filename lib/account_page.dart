import 'package:flutter/material.dart';

import 'account_details_page.dart';
import 'api.dart';
import 'crash_reports.dart';
import 'l10n.dart';
import 'parental_controls_page.dart';
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
  late Future<_AccountData> _data;

  // One key per section, so the section nav can scroll to it.
  final _overview = GlobalKey(), _requests = GlobalKey(), _linked = GlobalKey();
  final _security = GlobalKey(), _signedIn = GlobalKey();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() {
    // Friends and requests only feed the stat cards and the requests card:
    // unreachable, the page shows zeros rather than failing.
    _data = Future.wait([
      widget.api.me(),
      widget.api.sessions(),
      widget.api.friends().catchError((_) => <Friend>[]),
      widget.api.friendRequests().catchError((_) => FriendRequests(incoming: [], outgoing: [])),
    ]).then((r) => (
      r[0] as Account,
      r[1] as List<WebSession>,
      r[2] as List<Friend>,
      r[3] as FriendRequests,
    ));
  });

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.accountTitle)),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<_AccountData>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final (me, sessions, friends, requests) = snap.data!;
            final incoming = requests.incoming;
            // A Column rather than a ListView: the section nav scrolls to a
            // section by its key, and a lazy list has not built the far ones.
            return Column(
              children: [
                _SectionNav(sections: [
                  (Icons.home_outlined, l.accountOverview, _overview),
                  if (incoming.isNotEmpty) (Icons.person_add_alt, l.accountRequests, _requests),
                  (Icons.videogame_asset_outlined, l.accountLinked, _linked),
                  (Icons.shield_outlined, l.accountSecurity, _security),
                  (Icons.devices_outlined, l.accountSignedIn, _signedIn),
                ]),
                Expanded(
                  child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pagePadding(context, top: 16),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileCard(key: _overview, api: widget.api, me: me, onTap: () => _openDetails(me)),
                const SizedBox(height: 12),
                // IntrinsicHeight: the three cards match, sub line or not.
                IntrinsicHeight(
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Stat(value: friends.length, label: l.navFriends, sub: l.titlesOnlineCount(friends.where((f) => f.online).length)),
                    const SizedBox(width: 10),
                    _Stat(value: me.linkedPlatforms.length, label: l.accountLinked),
                    const SizedBox(width: 10),
                    _Stat(value: incoming.length, label: l.accountRequests),
                  ],
                  ),
                ),
                if (incoming.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SectionLabel(l.friendsIncoming, key: _requests, trailing: '${incoming.length}'),
                  for (final f in incoming)
                    StateRow(
                      name: f.displayName,
                      pill: l.friendsWantsToAdd,
                      state: RowState.warn,
                      leading: Avatar(
                        name: f.displayName,
                        avatarUrl: f.avatarUrl == null ? null : widget.api.absolute(f.avatarUrl!),
                      ),
                      trailing: RequestActions(
                        onDecline: () => _act(() => widget.api.declineFriend(f.accountId), l.commonDeclined),
                        onAccept: () => _act(() => widget.api.acceptFriend(f.accountId), l.friendsAccepted(f.displayName)),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                SectionLabel(l.accountLinked, key: _linked),
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
                          trailing: tileAction(context, TextButton(
                            onPressed: () => _unlink(ns),
                            child: Text(l.accountUnlink, style: TextStyle(color: t.bad)),
                          )),
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
                SectionLabel(l.accountSecurity, key: _security),
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
                        trailing: tileAction(context, me.emailVerified
                            ? null
                            : TextButton(
                                onPressed: () => _act(
                                  widget.api.resendVerification,
                                  l.accountVerifySent,
                                ),
                                child: Text(l.accountVerifyResend),
                              )),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.alternate_email),
                        title: Text(l.accountChangeEmail),
                        trailing: Icon(Icons.chevron_right, color: t.muted),
                        onTap: _changeEmail,
                      ),
                      const Divider(height: 1),
                      // Parental controls sit with the account rather than in
                      // the tab bar: it is something you set up once for a
                      // console, not somewhere you go every day.
                      ListTile(
                        leading: const Icon(Icons.family_restroom),
                        title: Text(l.parentalTitle),
                        trailing: Icon(Icons.chevron_right, color: t.muted),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ParentalControlsPage(api: widget.api),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(l.twoFactorTitle),
                        subtitle: Text(me.twoFactorEnabled ? l.accountTwoFactorOn : l.accountTwoFactorOff),
                        trailing: tileAction(context, me.twoFactorEnabled
                            ? TextButton(
                                onPressed: _disableTwoFactor,
                                child: Text(l.accountTurnOff, style: TextStyle(color: t.bad)),
                              )
                            : TextButton(
                                onPressed: _setUpTwoFactor,
                                child: Text(l.accountSetUp),
                              )),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionLabel(l.accountSignedIn, key: _signedIn, trailing: '${sessions.length}'),
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
                          trailing: tileAction(context, TextButton(
                            onPressed: () => _revoke(sessions[i]),
                            child: Text(
                              l.accountRevoke,
                              style: TextStyle(color: t.bad),
                            ),
                          )),
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
              ),
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

/// The website's profile card: the avatar and name on a flat tile, and the
/// friend code in a well
/// with its copy button — the code exists to be handed to someone else.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({super.key, required this.api, required this.me, required this.onTap});
  final OpenPakApi api;
  final Account me;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radiusLg), boxShadow: t.shadow),
      child: Material(
        color: t.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: t.cardLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // No cover band: the site's profile is the avatar and the
                    // name on a flat tile, the cover being a gradient it dropped.
                    Row(
                      children: [
                        AccountAvatar(api: api, account: me, size: 64),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                me.displayName.isEmpty ? l.accountYou : me.displayName,
                                style: const TextStyle(fontFamily: uiFont, fontSize: 24, fontWeight: FontWeight.w800),
                              ),
                              if (me.email.isNotEmpty)
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(me.email, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted)),
                                    ),
                                    if (me.emailVerified) ...[
                                      const SizedBox(width: 8),
                                      StatePill(text: l.accountEmailConfirmed, state: RowState.ok),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: t.muted),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Every code this account can be added by, each in its
                    // own well with a copy button, as on the website's banner.
                    for (final c in me.friendCodes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CodeWell(
                          label: switch (c.kind) {
                            'handle' => l.commonHandle,
                            'switch' => l.friendsKindSwitch,
                            '3ds' => l.friendsKind3ds,
                            'email' => l.friendsKindEmail,
                            _ => c.label, // Wii U · NNID, and whatever comes next
                          },
                          code: c.code,
                        ),
                      ),
                    if (me.friendCodes.isEmpty)
                      Text(l.accountNoFriendCode, style: TextStyle(color: t.muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One code in a well: its kind as an eyebrow, the code in monospace, a copy
/// button — the code exists to be handed to someone else.
class _CodeWell extends StatelessWidget {
  const _CodeWell({required this.label, required this.code});
  final String label;
  final String code;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: t.paper2,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontFamily: uiFont, color: t.muted, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                // One line, shrunk if it must: a code split across lines
                // gets copied down wrong.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    code,
                    maxLines: 1,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.7),
                  ),
                ),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: l.commonCopy,
            onPressed: () => copyToClipboard(context, code, l.commonFriendCodeCopied),
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

typedef _AccountData = (Account, List<WebSession>, List<Friend>, FriendRequests);

/// The site's section nav on a phone: a row of pill links that stays put
/// under the header and scrolls sideways; a tap brings the section into view.
class _SectionNav extends StatelessWidget {
  const _SectionNav({required this.sections});
  final List<(IconData, String, GlobalKey)> sections;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        child: Row(
          children: [
            for (final (icon, label, key) in sections)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  avatar: Icon(icon, size: 18, color: t.ink2),
                  label: Text(label),
                  onPressed: () {
                    final c = key.currentContext;
                    if (c != null) {
                      Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One of the three mini stat cards under the profile: a big number, its
/// label, and an optional line under it.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.sub});
  final int value;
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Expanded(
      child: Panel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontFamily: uiFont,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.ink2, fontSize: 13)),
              if (sub != null)
                Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

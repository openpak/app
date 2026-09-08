import 'package:flutter/material.dart';

import 'account_details_page.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Who you are, what is linked, and where you are signed in.
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
              return const ScrollableMessage(
                'Could not load. Pull down to try again.',
              );
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
                  child: me.linkedPlatforms.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Nothing linked yet. Link a console from its own '
                            'settings, or from the website.',
                            style: TextStyle(color: t.muted),
                          ),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < me.linkedPlatforms.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.videogame_asset_outlined),
                                title: Text(me.linkedPlatforms[i]),
                              ),
                            ],
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
                  onPressed: widget.onSignedOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: t.bad,
                    side: BorderSide(color: t.line),
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

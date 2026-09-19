import 'package:flutter/material.dart';

import 'api.dart';
import 'chat_page.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Friends, the requests waiting on either side, adding someone by code, and
/// the accounts you blocked.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<FriendsPage> createState() => FriendsPageState();
}

class FriendsPageState extends State<FriendsPage> {
  late Future<(List<Friend>, FriendRequests, List<BlockedAccount>)> _data;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() {
    _data = Future.wait([
      widget.api.friends(),
      widget.api.friendRequests(),
      // The block list is the least of this page: a failure there must not
      // take the friends down with it.
      widget.api.blocked().catchError((_) => <BlockedAccount>[]),
    ]).then((r) => (r[0] as List<Friend>, r[1] as FriendRequests, r[2] as List<BlockedAccount>));
  });

  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    }
    reload();
  }

  /// Undo right after, or Unblock from the Blocked list at the bottom later.
  Future<void> _block(Friend f) async {
    final l = context.l10n;
    try {
      await widget.api.blockAccount(f.accountId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.friendsBlockedToast(f.displayName)),
          action: SnackBarAction(
            label: l.commonUndo,
            onPressed: () => _act(() => widget.api.unblockAccount(f.accountId), l.friendsUnblocked),
          ),
        ));
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    }
    reload();
  }

  Future<void> _addByCode() async {
    final l = context.l10n;
    final code = await promptForText(
      context,
      title: l.friendsAddTitle,
      hint: 'SW-0000-0000-0000',
      help: l.friendsAddHelp,
    );
    if (code == null || code.trim().isEmpty) return;
    await _act(() => widget.api.addFriend(code.trim()), l.friendsRequestSent);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.friendsTitle),
        actions: [
          IconButton(
            tooltip: l.friendsMessagesTooltip,
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ConversationsPage(api: widget.api),
            )),
          ),
          IconButton(
            tooltip: l.friendsAddTooltip,
            icon: const Icon(Icons.person_add_alt),
            onPressed: _addByCode,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => reload(),
        child: FutureBuilder<(List<Friend>, FriendRequests, List<BlockedAccount>)>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final (friends, requests, blocked) = snap.data!;
            if (friends.isEmpty &&
                requests.incoming.isEmpty &&
                requests.outgoing.isEmpty &&
                blocked.isEmpty) {
              return ScrollableMessage(l.friendsEmpty);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (requests.incoming.isNotEmpty) ...[
                  SectionLabel(l.friendsIncoming),
                  ...requests.incoming.map(
                    (f) => StateRow(
                      name: f.displayName,
                      pill: l.friendsWantsToAdd,
                      state: RowState.warn,
                      leading: Avatar(name: f.displayName),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _act(
                              () => widget.api.declineFriend(f.accountId),
                              l.commonDeclined,
                            ),
                            child: Text(l.commonDecline, style: TextStyle(color: t.muted)),
                          ),
                          TextButton(
                            onPressed: () => _act(
                              () => widget.api.acceptFriend(f.accountId),
                              l.friendsAccepted(f.displayName),
                            ),
                            child: Text(l.friendsAccept),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                SectionLabel(l.friendsTitle, trailing: '${friends.length}'),
                if (friends.isEmpty)
                  Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.friendsNobody,
                        style: TextStyle(color: t.muted),
                      ),
                    ),
                  )
                else
                  ...friends.map(_friendRow),
                if (requests.outgoing.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SectionLabel(l.friendsWaiting),
                  ...requests.outgoing.map(
                    (f) => StateRow(
                      name: f.displayName,
                      pill: l.friendsRequestSentPill,
                      leading: Avatar(name: f.displayName, dim: true),
                    ),
                  ),
                ],
                if (blocked.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SectionLabel(l.friendsBlocked, trailing: '${blocked.length}'),
                  ...blocked.map(
                    (b) => StateRow(
                      name: b.displayName,
                      pill: b.blockedAt == null ? l.friendsBlocked : l.friendsBlockedSince(shortDate(l, b.blockedAt!)),
                      leading: Avatar(name: b.displayName, dim: true),
                      trailing: TextButton(
                        onPressed: () => _act(
                          () => widget.api.unblockAccount(b.accountId),
                          l.friendsUnblocked,
                        ),
                        child: Text(l.friendsUnblock),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      l.friendsBlockedNote,
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Online is the whole point of a friends list, so it is the tint. The pill
  /// says what they are playing when the adapter told us, and "Online" when it
  /// did not — a title id would mean nothing to a person.
  Widget _friendRow(Friend f) {
    final l = context.l10n;
    final playing = f.titleId?.isNotEmpty ?? false;
    return StateRow(
      name: f.displayName,
      pill: f.online ? (playing ? f.titleId! : l.friendsOnline) : l.friendsOffline,
      state: f.online ? RowState.ok : RowState.idle,
      leading: Avatar(name: f.displayName, online: f.online),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatPage(api: widget.api, peer: f.accountId, name: f.displayName),
      )),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'remove') {
            if (await confirm(context, l.friendsRemoveConfirm(f.displayName))) {
              await _act(() => widget.api.removeFriend(f.accountId), l.friendsRemoved);
            }
          } else if (v == 'block') {
            if (await confirm(
              context,
              l.friendsBlockConfirm(f.displayName),
              detail: l.friendsBlockDetail,
            )) {
              await _block(f);
            }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'remove', child: Text(l.friendsRemove)),
          PopupMenuItem(value: 'block', child: Text(l.friendsBlock)),
        ],
      ),
    );
  }
}

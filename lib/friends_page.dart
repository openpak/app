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
  late Future<(List<Friend>, FriendRequests, List<BlockedAccount>, List<CatalogItem>)> _data;

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
      // Same reasoning for the catalog: it only turns a title id into a name,
      // so a friend row falls back to the platform rather than losing the
      // whole page when the catalog cannot be reached.
      widget.api.requests().catchError((_) => <CatalogItem>[]),
    ]).then(
      (r) => (
        r[0] as List<Friend>,
        r[1] as FriendRequests,
        r[2] as List<BlockedAccount>,
        r[3] as List<CatalogItem>,
      ),
    );
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
        child: FutureBuilder<(List<Friend>, FriendRequests, List<BlockedAccount>, List<CatalogItem>)>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final (friends, requests, blocked, catalog) = snap.data!;
            // Title id → game name, the same catalog the Titles tab shows.
            // Only started games carry a name worth showing; features and
            // rows with no title id never match a friend's presence.
            final gameNames = {
              for (final c in catalog)
                if (c.isTitle && c.titleId.isNotEmpty) c.titleId.toUpperCase(): c.name,
            };
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
                  ...friends.map((f) => _friendRow(f, gameNames)),
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
  /// says what they are playing when the catalog can name it, the platform and
  /// "in a game" when it cannot, and "Online" when there is no session at all
  /// — never the bare title id, which would mean nothing to a person. Tapping
  /// the row opens the detail below it; the actions that used to live behind
  /// the tap and the overflow menu are icon buttons instead.
  Widget _friendRow(Friend f, Map<String, String> gameNames) {
    final l = context.l10n;
    final playing = f.titleId?.isNotEmpty ?? false;
    final gameName = playing ? gameNames[f.titleId!.toUpperCase()] : null;
    final platform = (f.namespace?.isEmpty ?? true) ? null : friendPlatformName(f.namespace!);
    final pill = !f.online
        ? l.friendsOffline
        : gameName ?? (playing ? [if (platform != null) platform, l.friendsInAGame].join(' · ') : l.friendsOnline);
    return StateRow(
      name: f.displayName,
      pill: pill,
      state: f.online ? RowState.ok : RowState.idle,
      leading: Avatar(name: f.displayName, online: f.online),
      expandedChild: _friendDetail(f, gameName, platform),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l.friendsMessageTooltip,
            icon: const Icon(Icons.chat_bubble_outline, size: 20),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChatPage(api: widget.api, peer: f.accountId, name: f.displayName),
            )),
          ),
          IconButton(
            tooltip: l.friendsRemove,
            icon: const Icon(Icons.person_remove_outlined, size: 20),
            onPressed: () async {
              if (await confirm(context, l.friendsRemoveConfirm(f.displayName))) {
                await _act(() => widget.api.removeFriend(f.accountId), l.friendsRemoved);
              }
            },
          ),
          IconButton(
            tooltip: l.friendsBlock,
            icon: const Icon(Icons.block, size: 20),
            onPressed: () async {
              if (await confirm(
                context,
                l.friendsBlockConfirm(f.displayName),
                detail: l.friendsBlockDetail,
              )) {
                await _block(f);
              }
            },
          ),
        ],
      ),
    );
  }

  /// What is under the disclosure: the game (art and name, or the platform
  /// and "in a game" when the catalog has no name for it), the platform, and
  /// when the session began. A friend's own friend code and the date the
  /// friendship was made are not in this reply — GET /me/friends carries
  /// account_id, display_name, online, title_id, namespace and since, and
  /// nothing else about the relationship — so neither is shown rather than
  /// making one up.
  Widget _friendDetail(Friend f, String? gameName, String? platform) {
    final l = context.l10n;
    final t = tokensOf(context);
    if (!f.online) {
      return Text(l.friendsOffline, style: TextStyle(color: t.muted, fontSize: 13));
    }
    final playing = f.titleId?.isNotEmpty ?? false;
    Widget row(Widget icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, height: 28, child: Center(child: icon)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: t.ink2, fontSize: 13))),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (playing)
          row(
            looksLikeSwitchTitleId(f.titleId!)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      widget.api.absolute('/titles/icon/${f.titleId}'),
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(Icons.videogame_asset_outlined, color: t.muted),
                    ),
                  )
                : Icon(Icons.videogame_asset_outlined, color: t.muted),
            gameName ?? l.friendsInAGame,
          ),
        if (platform != null) row(Icon(Icons.devices_outlined, color: t.muted, size: 20), platform),
        if (f.since != null)
          row(Icon(Icons.schedule_outlined, color: t.muted, size: 20), l.friendsOnlineSince(shortDateTime(l, f.since!))),
      ],
    );
  }
}

// ── Pure helpers, unit-tested ────────────────────────────────────────────────

/// A friend's session platform, in the app's own words rather than the
/// account core's wire namespace. Unlike widgets.dart's `platformNames` (built
/// for the shorter linked-consoles list), a friend's current console is
/// spelled out in full. An unrecognised namespace shows its own name,
/// capitalised, rather than nothing at all.
String friendPlatformName(String namespace) => switch (namespace) {
  'switch' => 'Nintendo Switch',
  'wiiu' => 'Wii U',
  '3ds' => 'Nintendo 3DS',
  _ => namespace.isEmpty ? namespace : namespace[0].toUpperCase() + namespace.substring(1),
};

/// Whether a title id is shaped like a Switch one — 16 hex digits — which is
/// the only console /titles/icon/{id} can draw an icon for. Same shape the
/// website checks before it calls out to nlib.
final _switchTitleId = RegExp(r'^[0-9A-Fa-f]{16}$');
bool looksLikeSwitchTitleId(String id) => _switchTitleId.hasMatch(id);

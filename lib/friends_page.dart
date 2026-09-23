import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'chat_page.dart';
import 'l10n.dart';
import 'theme.dart';
import 'titles_page.dart' show consoleAsset;
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
                      leading: Avatar(
                        name: f.displayName,
                        avatarUrl: f.avatarUrl != null
                            ? widget.api.absolute(f.avatarUrl!)
                            : null,
                      ),
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
                      leading: Avatar(
                        name: f.displayName,
                        dim: true,
                        avatarUrl: f.avatarUrl != null
                            ? widget.api.absolute(f.avatarUrl!)
                            : null,
                      ),
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
  /// says what they are playing and where ([friendPresenceText]) — never the
  /// bare title id, which would mean nothing to a person. Tapping
  /// the row opens the detail below it; the actions that used to live behind
  /// the tap and the overflow menu are icon buttons instead.
  Widget _friendRow(Friend f, Map<String, String> gameNames) {
    final l = context.l10n;
    final playing = f.titleId?.isNotEmpty ?? false;
    // The website's name first; the catalog's for an older server.
    final gameName = f.titleName ?? (playing ? gameNames[f.titleId!.toUpperCase()] : null);
    final ns = f.platform ?? f.namespace;
    final platform = (ns?.isEmpty ?? true) ? null : friendPlatformName(ns!);
    return StateRow(
      name: f.displayName,
      pill: friendPresenceText(l, f, catalogName: gameName),
      state: f.online ? RowState.ok : RowState.idle,
      leading: Avatar(
        name: f.displayName,
        online: f.online,
        avatarUrl: f.avatarUrl != null
            ? widget.api.absolute(f.avatarUrl!)
            : null,
      ),
      expandedChild: _friendDetail(f, gameName, platform, ns),
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
  /// and "in a game" when the catalog has no name for it), the platform with
  /// a chip for the client it runs on (Ryujinx, Cemu, the console itself...),
  /// and when the session began. A friend's own friend code and the date the
  /// friendship was made are not in this reply — GET /me/friends carries
  /// account_id, display_name, online, title_id, namespace and since, and
  /// nothing else about the relationship — so neither is shown rather than
  /// making one up.
  Widget _friendDetail(Friend f, String? gameName, String? platform, String? ns) {
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
        if (f.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const SizedBox(width: 36),
                if (platform != null) ...[
                  Flexible(child: Text(platform, style: TextStyle(color: t.ink2, fontSize: 13))),
                  const SizedBox(width: 8),
                ],
                FriendClientChip(label: f.label!, platform: ns),
              ],
            ),
          )
        else if (platform != null)
          row(Icon(Icons.devices_outlined, color: t.muted, size: 20), platform),
        if (f.since != null)
          row(Icon(Icons.schedule_outlined, color: t.muted, size: 20), l.friendsOnlineSince(shortDateTime(l, f.since!))),
      ],
    );
  }
}

/// The client a friend is on, as a small outlined chip with the console's
/// mark: "Ryujinx", "Cemu", "Switch"... The mark is the same file the Titles
/// tab draws; an unknown platform gets the generic one.
class FriendClientChip extends StatelessWidget {
  const FriendClientChip({super.key, required this.label, this.platform});
  final String label;
  final String? platform;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.line2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/consoles/${consoleAsset(friendConsole(platform), Theme.of(context).brightness)}.svg',
            width: 21,
            height: 14,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: t.ink2, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Pure helpers, unit-tested ────────────────────────────────────────────────

/// A friend row's pill. Offline is just that. Online, with a label from the
/// website (v0.50+): "{game} on {label}", "Playing on {label}" when the game
/// has no name, "Online on {label}" outside a game. Without one (an older
/// server) it is what the app always showed: the game's name, else the
/// platform and "In a game", else "Online". [catalogName] is the game's name
/// from wherever the caller found it.
String friendPresenceText(AppLocalizations l, Friend f, {String? catalogName}) {
  if (!f.online) return l.friendsOffline;
  final playing = (f.titleId?.isNotEmpty ?? false) || f.titleName != null;
  final game = f.titleName ?? catalogName;
  final label = f.label;
  if (label != null) {
    if (!playing) return l.friendsOnlineOn(label);
    return game != null ? l.friendsPlayingGameOn(game, label) : l.friendsPlayingOn(label);
  }
  if (game != null) return game;
  if (!playing) return l.friendsOnline;
  final ns = f.platform ?? f.namespace;
  return [if (ns != null && ns.isNotEmpty) friendPlatformName(ns), l.friendsInAGame].join(' · ');
}

/// The website presence platform, as the catalog's console name that
/// [consoleAsset] draws.
String friendConsole(String? platform) => switch (platform) {
  'switch' => 'Switch',
  'wiiu' => 'Wii U',
  '3ds' => '3DS',
  _ => '',
};

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

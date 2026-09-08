import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Friends, the requests waiting on either side, and adding someone by code.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<FriendsPage> createState() => FriendsPageState();
}

class FriendsPageState extends State<FriendsPage> {
  late Future<(List<Friend>, FriendRequests)> _data;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() {
    _data = Future.wait([widget.api.friends(), widget.api.friendRequests()])
        .then((r) => (r[0] as List<Friend>, r[1] as FriendRequests));
  });

  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
    reload();
  }

  Future<void> _addByCode() async {
    final code = await promptForText(
      context,
      title: 'Add a friend',
      hint: 'SW-0000-0000-0000',
      help: 'Their friend code, from their console or their account page.',
    );
    if (code == null || code.trim().isEmpty) return;
    await _act(() => widget.api.addFriend(code.trim()), 'Request sent.');
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            tooltip: 'Add by friend code',
            icon: const Icon(Icons.person_add_alt),
            onPressed: _addByCode,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => reload(),
        child: FutureBuilder<(List<Friend>, FriendRequests)>(
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
            final (friends, requests) = snap.data!;
            if (friends.isEmpty &&
                requests.incoming.isEmpty &&
                requests.outgoing.isEmpty) {
              return const ScrollableMessage(
                'No friends yet.\nAdd someone with the button above.',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (requests.incoming.isNotEmpty) ...[
                  const SectionLabel('Wants to be your friend'),
                  ...requests.incoming.map(
                    (f) => StateRow(
                      name: f.displayName,
                      pill: 'Wants to add you',
                      state: RowState.warn,
                      leading: Avatar(name: f.displayName),
                      trailing: TextButton(
                        onPressed: () => _act(
                          () => widget.api.acceptFriend(f.accountId),
                          'Added ${f.displayName}.',
                        ),
                        child: const Text('Accept'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                SectionLabel('Friends', trailing: '${friends.length}'),
                if (friends.isEmpty)
                  Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Nobody yet.',
                        style: TextStyle(color: t.muted),
                      ),
                    ),
                  )
                else
                  ...friends.map(_friendRow),
                if (requests.outgoing.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionLabel('Waiting for them'),
                  ...requests.outgoing.map(
                    (f) => StateRow(
                      name: f.displayName,
                      pill: 'Request sent',
                      leading: Avatar(name: f.displayName, dim: true),
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
    final playing = f.titleId?.isNotEmpty ?? false;
    return StateRow(
      name: f.displayName,
      pill: f.online ? (playing ? f.titleId! : 'Online') : 'Offline',
      state: f.online ? RowState.ok : RowState.idle,
      leading: Avatar(name: f.displayName, online: f.online),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'remove') {
            if (await confirm(context, 'Remove ${f.displayName}?')) {
              await _act(() => widget.api.removeFriend(f.accountId), 'Removed.');
            }
          } else if (v == 'block') {
            if (await confirm(
              context,
              'Block ${f.displayName}?',
              detail: 'They are removed as a friend and cannot invite you.',
            )) {
              await _act(() => widget.api.blockAccount(f.accountId), 'Blocked.');
            }
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'remove', child: Text('Remove')),
          PopupMenuItem(value: 'block', child: Text('Block')),
        ],
      ),
    );
  }

}

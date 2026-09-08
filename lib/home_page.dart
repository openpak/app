import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';

/// Friends and invitations, the two things this app exists for.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api, required this.onSignedOut});
  final OpenPakApi api;
  final Future<void> Function() onSignedOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  late Future<List<Friend>> _friends;
  late Future<List<Invitation>> _invitations;
  String? _friendCode;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadFriendCode();
  }

  void _reload() {
    _friends = _guard(widget.api.friends());
    _invitations = _guard(widget.api.invitations());
  }

  /// Any 401 means the bearer died — revoked on the website, or the account
  /// session ended. Signing out is the only honest response.
  Future<T> _guard<T>(Future<T> f) async {
    try {
      return await f;
    } on ApiException catch (e) {
      if (e.unauthorized) unawaited(widget.onSignedOut());
      rethrow;
    }
  }

  Future<void> _loadFriendCode() async {
    try {
      final me = await widget.api.me();
      if (mounted) setState(() => _friendCode = me.friendCode);
    } catch (_) {
      // The friend code is decoration on this screen; its absence is normal
      // for an account with no console linked.
    }
  }

  Future<void> _refresh() async {
    setState(_reload);
    await Future.wait([
      _friends.catchError((_) => <Friend>[]),
      _invitations.catchError((_) => <Invitation>[]),
    ]);
  }

  Future<void> _decline(Invitation inv) async {
    try {
      await widget.api.decline(inv.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Friends' : 'Invitations'),
        actions: [
          if (_friendCode != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _friendCode!,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => widget.onSignedOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _tab == 0 ? _friendsList() : _invitationsList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Friends'),
          NavigationDestination(icon: Icon(Icons.mail_outline), label: 'Invitations'),
        ],
      ),
    );
  }

  Widget _friendsList() {
    return FutureBuilder<List<Friend>>(
      future: _friends,
      builder: (context, snap) => _list<Friend>(
        snap,
        empty: 'No friends yet. Add someone by friend code on the website.',
        itemBuilder: (f) => ListTile(
          leading: CircleAvatar(
            backgroundColor: f.online
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
            child: Text(
              f.displayName.isEmpty ? '?' : f.displayName.characters.first.toUpperCase(),
            ),
          ),
          title: Text(f.displayName),
          // Offline friends stay in the list rather than disappearing, which
          // is why the server reports online:false instead of omitting them.
          subtitle: Text(
            f.online
                ? (f.titleId?.isNotEmpty ?? false)
                      ? 'Playing ${f.titleId}'
                      : 'Online'
                : 'Offline',
          ),
        ),
      ),
    );
  }

  Widget _invitationsList() {
    return FutureBuilder<List<Invitation>>(
      future: _invitations,
      builder: (context, snap) => _list<Invitation>(
        snap,
        empty: 'Nothing waiting for you.',
        itemBuilder: (inv) => ListTile(
          title: Text('${inv.from} invited you'),
          subtitle: Text(inv.expired ? 'Expired' : inv.titleId),
          trailing: TextButton(
            onPressed: () => _decline(inv),
            child: const Text('Decline'),
          ),
        ),
      ),
    );
  }

  /// One list shape for both tabs: a scrollable is always returned so
  /// pull-to-refresh works even when empty or failed.
  Widget _list<T>(
    AsyncSnapshot<List<T>> snap, {
    required String empty,
    required Widget Function(T) itemBuilder,
  }) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = snap.data ?? const [];
    if (snap.hasError) {
      return _message('Could not load. Pull down to try again.');
    }
    if (items.isEmpty) return _message(empty);
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => itemBuilder(items[i]),
    );
  }

  Widget _message(String text) => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    ],
  );
}

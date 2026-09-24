import 'package:flutter/material.dart';

import 'account_page.dart';
import 'api.dart';
import 'friends_page.dart';
import 'invitations_page.dart';
import 'l10n.dart';
import 'saves_page.dart';
import 'theme.dart';
import 'titles_page.dart';
import 'widgets.dart';

/// The signed-in app: three destinations, each owning its own loading and
/// refresh. Pages are kept alive so switching tabs does not refetch.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, required this.onSignedOut});
  final OpenPakApi api;
  final Future<void> Function() onSignedOut;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  late final List<Widget> _pages = [
    FriendsPage(api: widget.api),
    InvitationsPage(api: widget.api),
    TitlesPage(api: widget.api),
    SavesPage(api: widget.api),
    AccountPage(api: widget.api, onSignedOut: widget.onSignedOut),
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      // The pages scroll under the tab bar, which blurs them, as the site's does.
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: glass(DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: tokensOf(context).line))),
        child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: l.navFriends,
          ),
          NavigationDestination(
            icon: Icon(Icons.mail_outline),
            selectedIcon: Icon(Icons.mail),
            label: l.navInvitations,
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: l.navTitles,
          ),
          NavigationDestination(
            icon: Icon(Icons.save_outlined),
            selectedIcon: Icon(Icons.save),
            label: l.navSaves,
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: l.navAccount,
          ),
        ],
      ))),
    );
  }
}

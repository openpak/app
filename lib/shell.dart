import 'package:flutter/material.dart';

import 'account_page.dart';
import 'api.dart';
import 'friends_page.dart';
import 'invitations_page.dart';
import 'saves_page.dart';
import 'titles_page.dart';

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
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Friends',
          ),
          NavigationDestination(
            icon: Icon(Icons.mail_outline),
            selectedIcon: Icon(Icons.mail),
            label: 'Invitations',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'Titles',
          ),
          NavigationDestination(
            icon: Icon(Icons.save_outlined),
            selectedIcon: Icon(Icons.save),
            label: 'Saves',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

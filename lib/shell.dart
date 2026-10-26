import 'package:flutter/material.dart';

import 'account_page.dart';
import 'api.dart';
import 'friends_page.dart';
import 'invitations_page.dart';
import 'l10n.dart';
import 'pakka.dart';
import 'saves_page.dart';
import 'theme.dart';
import 'titles_page.dart';
import 'widgets.dart';

/// The signed-in app: three destinations, each owning its own loading and
/// refresh. Pages are kept alive so switching tabs does not refetch.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, required this.onSignedOut, this.pakka});
  final OpenPakApi api;
  final Future<void> Function() onSignedOut;

  /// The diagnostics client, null when this build has no Pakka endpoint.
  final PakkaApi? pakka;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  late final List<Widget> _pages = [
    FriendsPage(api: widget.api),
    InvitationsPage(api: widget.api),
    TitlesPage(api: widget.api, pakka: widget.pakka),
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
        // Five labels in 390px: past 1.15× "Einladungen" breaks mid-word, so
        // the bar stops growing there, as system tab bars do.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: NavWell(Icons.people_outline),
            selectedIcon: NavWell(Icons.people, selected: true),
            label: l.navFriends,
          ),
          NavigationDestination(
            icon: NavWell(Icons.mail_outline),
            selectedIcon: NavWell(Icons.mail, selected: true),
            label: l.navInvitations,
          ),
          NavigationDestination(
            icon: NavWell(Icons.sports_esports_outlined),
            selectedIcon: NavWell(Icons.sports_esports, selected: true),
            label: l.navTitles,
          ),
          NavigationDestination(
            icon: NavWell(Icons.save_outlined),
            selectedIcon: NavWell(Icons.save, selected: true),
            label: l.navSaves,
          ),
          NavigationDestination(
            icon: NavWell(Icons.person_outline),
            selectedIcon: NavWell(Icons.person, selected: true),
            label: l.navAccount,
          ),
        ],
      )))),
    );
  }
}

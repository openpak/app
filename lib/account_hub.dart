import 'package:flutter/material.dart';

import 'activity_page.dart';
import 'api.dart';
import 'l10n.dart';
import 'operator_page.dart';
import 'rankings_page.dart';
import 'rewards_page.dart';
import 'sites_page.dart';
import 'support_page.dart';
import 'theme.dart';
import 'trophies_page.dart';
import 'widgets.dart';

/// The account area's way in to everything that is yours but not a tab: three
/// small groups of cards under the profile, so the bottom bar stays at five.
class AccountHub extends StatelessWidget {
  const AccountHub({super.key, required this.api});
  final OpenPakApi api;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget group(String label, List<_Entry> entries) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(label),
        Panel(
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _HubTile(entries[i]),
              ],
            ],
          ),
        ),
      ],
    );
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        group(l.hubPlay, [
          _Entry(Icons.emoji_events_outlined, l.rewardsTitle, l.hubRewardsSub, () => open(RewardsPage(api: api))),
          _Entry(Icons.military_tech_outlined, l.trophiesTitle, l.hubTrophiesSub, () => open(TrophiesPage(api: api))),
          _Entry(Icons.timeline, l.activityTitle, l.hubActivitySub, () => open(ActivityPage(api: api))),
          _Entry(Icons.leaderboard_outlined, l.rankingsTitle, l.hubRankingsSub, () => open(RankingsPage(api: api))),
        ]),
        const SizedBox(height: 12),
        group(l.hubExplore, [
          _Entry(Icons.travel_explore, l.sitesTitle, l.hubSitesSub, () => open(SitesPage(api: api))),
        ]),
        const SizedBox(height: 12),
        group(l.hubHelp, [
          _Entry(Icons.support_agent, l.supportTitle, l.hubSupportSub, () => open(SupportPage(api: api))),
          _Entry(Icons.dns_outlined, l.operatorTitle, l.hubOperatorSub, () => open(OperatorPage(api: api))),
        ]),
      ],
    );
  }
}

class _Entry {
  const _Entry(this.icon, this.title, this.sub, this.onTap);
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
}

class _HubTile extends StatelessWidget {
  const _HubTile(this.e);
  final _Entry e;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListTile(
      leading: Icon(e.icon),
      title: Text(e.title),
      subtitle: Text(e.sub, style: TextStyle(color: t.muted)),
      trailing: Icon(Icons.chevron_right, color: t.muted),
      onTap: e.onTap,
    );
  }
}

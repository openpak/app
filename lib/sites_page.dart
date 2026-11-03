import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'l10n.dart';
import 'open_sites.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openSite(OpenSite s) =>
    launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication);

/// The Open sites' own words, by key.
String siteLine(AppLocalizations l, String key) => switch (key) {
  'opensplat' => l.sitesOpensplatLine,
  'openkart' => l.sitesOpenkartLine,
  'openmaker' => l.sitesOpenmakerLine,
  'openverse' => l.sitesOpenverseLine,
  _ => '',
};

String siteGames(AppLocalizations l, String key) => switch (key) {
  'opensplat' => l.sitesOpensplatGames,
  'openkart' => l.sitesOpenkartGames,
  'openmaker' => l.sitesOpenmakerGames,
  'openverse' => l.sitesOpenverseGames,
  _ => '',
};

/// Tests switch the network fetch off; the fallback icon then stands in.
bool siteMarksFromNetwork = true;

/// A site's mark, from the website, with a plain icon when it cannot be fetched.
class SiteMark extends StatelessWidget {
  const SiteMark({
    super.key,
    required this.api,
    required this.site,
    this.size = 72,
  });
  final OpenPakApi api;
  final OpenSite site;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.travel_explore,
      size: size * 0.6,
      color: tokensOf(context).muted,
    );
    return SizedBox.square(
      dimension: size,
      child: !siteMarksFromNetwork
          ? fallback
          : SvgPicture.network(
              api.absolute(site.mark),
              width: size,
              height: size,
              excludeFromSemantics: true,
              placeholderBuilder: (_) => fallback,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// The companion sites; each opens in the browser.
class SitesPage extends StatelessWidget {
  const SitesPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = tokensOf(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.sitesTitle)),
      body: ListView(
        padding: pagePadding(context, top: 12),
        children: [
          Text(l.sitesSub, style: TextStyle(color: t.ink2, height: 1.4)),
          const SizedBox(height: 14),
          for (final s in openSites)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SiteMark(api: api, site: s),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  siteLine(l, s.key),
                                  style: TextStyle(color: t.ink2, height: 1.35),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${l.sitesGames} ${siteGames(l, s.key)}',
                                  style: TextStyle(
                                    color: t.muted,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => openSite(s),
                        child: Text(l.sitesOpen(s.name)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

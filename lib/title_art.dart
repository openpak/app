import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'titles_page.dart' show consoleAsset, statusLabel, statusState;
import 'widgets.dart';

/// A game's picture, as the website's titles page draws it: the cover tile or Switch icon the server names
/// (`art_url`), and when there is none, or it fails to load, the console's mark on a quiet tile. Never a
/// broken image.
class TitleArt extends StatelessWidget {
  const TitleArt({super.key, required this.api, required this.item, this.radius = 12});
  final OpenPakApi api;
  final CatalogItem item;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final placeholder = Container(
      color: t.paper2,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: item.console.isEmpty
          ? Icon(Icons.sports_esports_outlined, color: t.faint, size: 32)
          : SvgPicture.asset(
              'assets/consoles/${consoleAsset(item.console, Theme.of(context).brightness)}.svg',
              width: 72,
              height: 48,
              semanticsLabel: item.console,
            ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: item.artUrl.isEmpty
          ? placeholder
          : Image.network(
              api.absolute(item.artUrl),
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}

/// One game in the Titles grid: its picture, its name and its status.
class TitleTile extends StatelessWidget {
  const TitleTile({super.key, required this.api, required this.item, required this.onTap});
  final OpenPakApi api;
  final CatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final (bg, line, ink) = stateColors(context, statusState(item.status));
    return Container(
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: t.cardLine),
        boxShadow: t.shadow,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 1, child: TitleArt(api: api, item: item)),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.2),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: bg, border: Border.all(color: line), borderRadius: BorderRadius.circular(99)),
                child: Text(
                  statusLabel(context.l10n, item.status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ink, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small pieces of the Rewards screens: pictures with a placeholder, the
/// mission and ladder tiles, shop cards, history cards. Colours come from the
/// tokens only, so an equipped Rewards theme re-colours all of it.
library;

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// A picture from the site (a public path such as /account/rewards/preview/x),
/// or a quiet placeholder when it is missing or cannot load.
class RewardsImage extends StatelessWidget {
  const RewardsImage({super.key, required this.api, required this.path, this.width = 56, this.height, this.circle = false});
  final OpenPakApi api;
  final String path;
  final double width;
  final double? height;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final h = height ?? width;
    final placeholder = Container(
      width: width,
      height: h,
      color: t.paper2,
      alignment: Alignment.center,
      child: Icon(Icons.emoji_events_outlined, color: t.faint, size: (width < h ? width : h) * 0.45),
    );
    final Widget img = path.isEmpty
        ? placeholder
        : Image.network(
            api.absolute(path),
            width: width,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
            loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
          );
    return circle
        ? ClipOval(child: img)
        : ClipRRect(borderRadius: BorderRadius.circular(radiusCard - 4), child: img);
  }
}

/// A small tinted label ("Completed", "120 pts").
class RewardsBadge extends StatelessWidget {
  const RewardsBadge(this.text, {super.key, this.state = RowState.idle});
  final String text;
  final RowState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final (bg, line, fg) = switch (state) {
      RowState.ok => (t.okWeak, t.okLine, t.ok),
      RowState.beta => (t.accentWeak, t.accentLine, Theme.of(context).colorScheme.primary),
      RowState.warn => (t.warnWeak, t.warnLine, t.warn),
      RowState.bad => (t.badWeak, t.badLine, t.bad),
      RowState.idle => (t.paper2, t.line, t.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: line),
      ),
      child: Text(
        text,
        style: TextStyle(fontFamily: uiFont, fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// The earned tiers of a ladder as a row of dots.
class TierPips extends StatelessWidget {
  const TierPips({super.key, required this.pips, required this.earned});
  final List<bool> pips;
  final int earned;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: context.l10n.rewardsTierPips(earned, pips.length),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final on in pips)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? primary : Colors.transparent,
                  border: Border.all(color: on ? primary : t.line2, width: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A card: the site's flat tile with an optional tap.
class RewardsCard extends StatelessWidget {
  const RewardsCard({super.key, required this.child, this.onTap, this.dim = false});
  final Widget child;
  final VoidCallback? onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Opacity(
      opacity: dim ? 0.7 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(radiusCard), boxShadow: t.shadow),
        child: Material(
          color: t.raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard),
            side: BorderSide(color: t.cardLine),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: child),
        ),
      ),
    );
  }
}

/// What a mission tile offers under its text.
enum TileMode { work, mine, done }

/// A mission or ladder tile as a card: art, name, pips, progress, and the one
/// action it has (Claim when ready, Equip in My items).
class MissionCard extends StatelessWidget {
  const MissionCard({
    super.key,
    required this.api,
    required this.tile,
    required this.mode,
    required this.frozen,
    required this.busy,
    required this.onOpen,
    this.onClaim,
    this.onEquip,
  });
  final OpenPakApi api;
  final RewardsTile tile;
  final TileMode mode;
  final bool frozen, busy;
  final VoidCallback onOpen;
  final VoidCallback? onClaim, onEquip;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    final showBar = mode == TileMode.work && tile.state == 'progress';
    return RewardsCard(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RewardsImage(api: api, path: tile.img, width: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tile.label.isEmpty ? tile.name : tile.label,
                        style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800, fontSize: 15.5),
                      ),
                      if (tile.pips.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        TierPips(pips: tile.pips, earned: tile.earned),
                      ],
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(tile.progress, style: TextStyle(color: t.ink2, fontSize: 13)),
                          if (tile.complete && mode != TileMode.work) RewardsBadge(l.rewardsCompleted, state: RowState.ok),
                        ],
                      ),
                      if (mode == TileMode.work && !tile.ready && tile.reward.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(tile.reward, style: TextStyle(color: t.muted, fontSize: 12.5)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (showBar) ...[
              const SizedBox(height: 10),
              ProgressBar(percent: tile.percent),
            ],
            if (mode == TileMode.work && tile.ready) ...[
              const SizedBox(height: 10),
              FilledButton(
                onPressed: frozen || busy ? null : onClaim,
                child: Text(tile.claimText.isEmpty ? l.rewardsClaim : tile.claimText, textAlign: TextAlign.center),
              ),
            ],
            if (mode == TileMode.mine) ...[
              const SizedBox(height: 10),
              EquipButton(equipped: tile.equipped, disabled: frozen || busy, onPressed: onEquip),
            ],
          ],
        ),
      ),
    );
  }
}

/// Equipped (tap to unequip) or Equip.
class EquipButton extends StatelessWidget {
  const EquipButton({super.key, required this.equipped, required this.disabled, required this.onPressed});
  final bool equipped, disabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return equipped
        ? OutlinedButton.icon(
            onPressed: disabled ? null : onPressed,
            icon: const Icon(Icons.check, size: 18),
            label: Text(l.rewardsEquipped),
          )
        : FilledButton(onPressed: disabled ? null : onPressed, child: Text(l.rewardsEquip));
  }
}

/// The site's thin progress bar, in the accent.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: percent.clamp(0, 100) / 100,
        minHeight: 8,
        backgroundColor: t.sunk,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// One line of the points history, as a card.
class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.api, required this.entry});
  final OpenPakApi api;
  final RewardsEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return RewardsCard(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            RewardsImage(api: api, path: entry.img, width: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (entry.sub.isNotEmpty) Text(entry.sub, style: TextStyle(color: t.muted, fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              entry.points,
              style: TextStyle(
                fontFamily: uiFont,
                fontWeight: FontWeight.w800,
                color: entry.delta > 0 ? t.ok : t.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shelf item as a card: art, name, price. [footer] holds Preview or Equip.
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.api,
    required this.item,
    required this.wide,
    this.onTap,
    this.showPrice = true,
    this.footer,
    this.dim = false,
  });
  final OpenPakApi api;
  final RewardsItem item;
  final bool wide, showPrice, dim;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return RewardsCard(
      onTap: onTap,
      dim: dim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) => RewardsImage(
              api: api,
              path: item.img,
              width: c.maxWidth,
              height: wide ? c.maxWidth * 0.5 : c.maxWidth,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                if (item.when.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(item.when, style: TextStyle(color: t.muted, fontSize: 12.5)),
                  ),
                if (showPrice && item.price != null) ...[
                  const SizedBox(height: 6),
                  RewardsBadge(l.rewardsPts(item.price!), state: item.affordable && !item.soon ? RowState.beta : RowState.idle),
                ],
              ],
            ),
          ),
          if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), child: footer),
        ],
      ),
    );
  }
}

/// Cards laid out in equal columns that follow the width.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, required this.wide});
  final List<Widget> children;
  final bool wide;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const gap = 10.0;
      final cols = wide ? (c.maxWidth >= 640 ? 2 : 1) : (c.maxWidth >= 640 ? 4 : 2);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    },
  );
}

/// A pill the person picks: a tab or a kind filter.
class RewardsChoice extends StatelessWidget {
  const RewardsChoice({super.key, required this.label, required this.selected, required this.onTap, this.count});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.onSurface : t.raised,
        shape: StadiumBorder(side: BorderSide(color: selected ? scheme.onSurface : t.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: uiFont,
                    fontWeight: FontWeight.w700,
                    color: selected ? scheme.surface : scheme.onSurface,
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      '$count',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: scheme.onPrimary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

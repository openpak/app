import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'rewards_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// What the app knows about Rewards without opening them: the balance, how many rewards wait to be claimed and
/// the mission being worked on. The Account card shows it and the Account tab wears the count. Loaded quietly;
/// a deployment without rewards, or any failure, leaves it empty and nothing is drawn.
class RewardsGlance extends ChangeNotifier {
  RewardsView? view;

  int get ready => view?.ready ?? 0;

  Future<void> load(OpenPakApi api) async {
    try {
      view = await api.rewards();
    } catch (_) {
      view = null;
    }
    notifyListeners();
  }

  void clear() {
    view = null;
    notifyListeners();
  }
}

/// The card under the profile on Account: balance, what is ready, what is next. Opens Rewards.
class RewardsSummaryCard extends StatelessWidget {
  const RewardsSummaryCard({super.key, required this.api, required this.glance});
  final OpenPakApi api;
  final RewardsGlance glance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: glance,
      builder: (context, _) {
        final v = glance.view;
        if (v == null) return const SizedBox.shrink();
        final l = context.l10n;
        final t = tokensOf(context);
        final next = v.readyTiles.isNotEmpty ? v.readyTiles.first : (v.tiles.isNotEmpty ? v.tiles.first : null);
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Panel(
            child: InkWell(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RewardsPage(api: api)));
                unawaited(glance.load(api)); // claiming or buying there changes the card and the tab's count
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    if (next != null && next.img.isNotEmpty) ...[
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: Image.network(
                          api.absolute(next.img),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(Icons.emoji_events_outlined, color: t.muted, size: 32),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ] else ...[
                      Icon(Icons.emoji_events_outlined, color: t.muted, size: 32),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.rewardsTitle, style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800, fontSize: 16)),
                          Text(l.rewardsGlanceBalance(v.balance), style: TextStyle(color: t.muted, fontSize: 13)),
                          const SizedBox(height: 4),
                          if (v.ready > 0)
                            Text(l.rewardsGlanceReady(v.ready), style: TextStyle(color: t.ok, fontWeight: FontWeight.w700, fontSize: 13.5))
                          else if (next != null)
                            Text(
                              '${l.rewardsGlanceNext(next.label.isEmpty ? next.name : next.label)} · ${next.progress}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t.ink2, fontSize: 13),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: t.muted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Buying a shop item: the confirm dialog (art, price, balance after) and the
/// redeem call, shared by the Shop tab and the theme preview bar.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'rewards_cards.dart';
import 'theme.dart';
import 'widgets.dart';

/// One idempotency key per purchase attempt: a retry after a lost answer
/// sends the same key, so the item cannot be bought twice.
String newIdempotencyKey() {
  final r = Random.secure();
  return List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
}

enum BuyResult { bought, preview }

/// Asks before spending. Returns [BuyResult.bought] after a successful
/// purchase, [BuyResult.preview] if the person chose to preview a theme
/// instead, null if they backed out.
Future<BuyResult?> showBuyDialog(
  BuildContext context, {
  required OpenPakApi api,
  required RewardsItem item,
  required int balance,
  required bool frozen,
  bool canPreview = true,
}) => showDialog<BuyResult>(
  context: context,
  builder: (_) => _BuyDialog(api: api, item: item, balance: balance, frozen: frozen, canPreview: canPreview),
);

class _BuyDialog extends StatefulWidget {
  const _BuyDialog({required this.api, required this.item, required this.balance, required this.frozen, required this.canPreview});
  final OpenPakApi api;
  final RewardsItem item;
  final int balance;
  final bool frozen, canPreview;

  @override
  State<_BuyDialog> createState() => _BuyDialogState();
}

class _BuyDialogState extends State<_BuyDialog> {
  final _key = newIdempotencyKey();
  bool _working = false;
  String? _error;

  Future<void> _buy() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.api.redeemReward(widget.item.id, idempotencyKey: _key);
      if (mounted) Navigator.pop(context, BuyResult.bought);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = apiErrorText(context.l10n, e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = LoadFailure.reasonOf(context.l10n, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = tokensOf(context);
    final item = widget.item;
    final price = item.price ?? 0;
    final need = item.price == null ? 0 : (price - widget.balance).clamp(0, 1 << 31);
    final canBuy = !widget.frozen && item.price != null && need == 0 && !_working;
    Widget fact(String k, String v) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(k, style: TextStyle(color: t.muted))),
          const SizedBox(width: 12),
          Flexible(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
    return AlertDialog(
      scrollable: true,
      title: Text(item.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: RewardsImage(api: widget.api, path: item.img, width: item.wide ? 240 : 128, height: item.wide ? 120 : 128),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(item.kindLabel, style: TextStyle(color: t.muted)),
              if (item.limited) RewardsBadge(l.rewardsLimited, state: RowState.warn),
            ],
          ),
          if (item.description.isNotEmpty) ...[const SizedBox(height: 8), Text(item.description)],
          const SizedBox(height: 8),
          fact(l.rewardsDlgPrice, l.rewardsPoints(price)),
          fact(l.rewardsDlgBalance, l.rewardsPoints(widget.balance)),
          if (need == 0 && item.price != null) fact(l.rewardsDlgAfter, l.rewardsPoints(widget.balance - price)),
          if (item.where.isNotEmpty) fact(l.rewardsDlgWhere, item.where),
          const SizedBox(height: 12),
          if (widget.frozen)
            _Say(l.rewardsFrozen, bad: true)
          else if (need > 0)
            _Say(l.rewardsDlgShort(need))
          else
            Text(l.rewardsDlgAsk(price, item.name), style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800)),
          if (item.limited) Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.rewardsDlgLimited, style: TextStyle(color: t.muted, fontSize: 13))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: _Say(_error!, bad: true)),
        ],
      ),
      actions: [
        TextButton(onPressed: _working ? null : () => Navigator.pop(context), child: Text(l.rewardsDlgCancel)),
        if (item.kind == 'theme' && widget.canPreview)
          TextButton(onPressed: _working ? null : () => Navigator.pop(context, BuyResult.preview), child: Text(l.rewardsPreview)),
        FilledButton(onPressed: canBuy ? _buy : null, child: Text(_working ? l.rewardsDlgWorking : l.rewardsDlgConfirm(price))),
      ],
    );
  }
}

class _Say extends StatelessWidget {
  const _Say(this.text, {this.bad = false});
  final String text;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bad ? t.badWeak : t.warnWeak,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: bad ? t.badLine : t.warnLine),
      ),
      child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
    );
  }
}

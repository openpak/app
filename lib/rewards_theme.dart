/// The equipped Rewards theme as app state: it re-colours the whole app, a
/// preview borrows it temporarily, and a bar on every screen says so.
library;

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'rewards_buy.dart';
import 'theme.dart';
import 'widgets.dart';

/// A theme being tried on. In memory only: a restart forgets it.
class ThemePreview {
  ThemePreview({required this.item, required this.theme});
  final RewardsItem item;
  final RewardsTheme theme;
}

class RewardsThemeController extends ChangeNotifier {
  RewardsThemeController(this.api, {this.navigatorKey});
  final OpenPakApi api;

  /// Where dialogs started from the preview bar open (the bar itself sits
  /// above the app's Navigator).
  final GlobalKey<NavigatorState>? navigatorKey;

  RewardsTheme? _equipped;
  ThemePreview? _preview;
  int _generation = 0;
  late ThemeData _light = openPakLight(), _dark = openPakDark();

  RewardsTheme? get equipped => _equipped;
  ThemePreview? get preview => _preview;
  ThemeData get light => _light;
  ThemeData get dark => _dark;

  RewardsTheme? get _active => _preview?.theme ?? _equipped;

  void _rebuild() {
    final a = _active;
    final ok = a != null && themeUsable(a.light, a.dark);
    _light = openPakLight(ok ? a.light : null);
    _dark = openPakDark(ok ? a.dark : null);
    notifyListeners();
  }

  /// Fetches the equipped theme. Never throws and never blocks anything: on
  /// any failure the app simply keeps the look it has.
  Future<void> load() async {
    final gen = ++_generation;
    try {
      final t = await api.equippedTheme();
      if (gen != _generation) return;
      _equipped = t;
    } catch (_) {
      return;
    }
    _rebuild();
  }

  /// Sign-out: back to the default look.
  void clear() {
    _generation++;
    _equipped = null;
    _preview = null;
    _rebuild();
  }

  /// Try [item] on, app-wide. False when its tokens cannot be loaded or used.
  Future<bool> startPreview(RewardsItem item) async {
    try {
      final t = await api.shopTheme(item.id);
      if (!themeUsable(t.light, t.dark)) return false;
      _preview = ThemePreview(item: item, theme: t);
      _rebuild();
      return true;
    } catch (_) {
      return false;
    }
  }

  void stopPreview() {
    if (_preview == null) return;
    _preview = null;
    _rebuild();
  }

  /// Equip the previewed (owned) theme.
  Future<void> equipPreview() async {
    final p = _preview;
    if (p == null) return;
    await api.equipReward('theme', p.item.id);
    _preview = null;
    await load();
    _rebuild();
  }

  /// Buy the previewed theme from the bar: shows the same confirm dialog.
  /// Returns a message to tell the person, or null.
  Future<String?> buyPreview() async {
    final p = _preview;
    final ctx = navigatorKey?.currentContext;
    if (p == null || ctx == null) return null;
    final view = await api.rewards();
    RewardsItem? item;
    for (final g in view.shop) {
      for (final i in g.items) {
        if (i.id == p.item.id) item = i;
      }
    }
    if (!ctx.mounted) return null;
    if (item == null) {
      stopPreview();
      return null;
    }
    final r = await showBuyDialog(ctx, api: api, item: item, balance: view.balance, frozen: view.frozen, canPreview: false);
    if (r == BuyResult.bought) {
      stopPreview();
      return ctx.mounted ? ctx.l10n.rewardsMsgRedeemed(item.name) : null;
    }
    return null;
  }
}

/// Reaches the controller from any screen; null in a tree without one.
class RewardsThemeScope extends InheritedNotifier<RewardsThemeController> {
  const RewardsThemeScope({super.key, required RewardsThemeController controller, required super.child})
    : super(notifier: controller);

  static RewardsThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RewardsThemeScope>()?.notifier;
}

/// Wraps every screen (MaterialApp.builder): the app, and under it the
/// preview bar while a theme is being tried on.
class ThemePreviewHost extends StatelessWidget {
  const ThemePreviewHost({super.key, required this.controller, required this.child});
  final RewardsThemeController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final p = controller.preview;
      // One structure with or without the bar, so the Navigator below is
      // never re-parented when a preview starts or stops.
      return Column(
        children: [
          // The bar takes the bottom inset, so the page above must not.
          Expanded(child: MediaQuery.removePadding(context: context, removeBottom: p != null, child: child)),
          if (p != null) ThemePreviewBar(controller: controller, preview: p),
        ],
      );
    },
  );
}

class ThemePreviewBar extends StatefulWidget {
  const ThemePreviewBar({super.key, required this.controller, required this.preview});
  final RewardsThemeController controller;
  final ThemePreview preview;

  @override
  State<ThemePreviewBar> createState() => _ThemePreviewBarState();
}

class _ThemePreviewBarState extends State<ThemePreviewBar> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action) async {
    setState(() => _busy = true);
    String? message;
    try {
      message = await action();
    } on ApiException catch (e) {
      if (mounted) message = apiErrorText(context.l10n, e);
    } catch (e) {
      if (mounted) message = LoadFailure.reasonOf(context.l10n, e);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = tokensOf(context);
    final item = widget.preview.item;
    final owned = item.owned;
    final c = widget.controller;
    return Material(
      color: t.raised,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line2, width: 1.5))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Semantics(
              container: true,
              label: l.rewardsPreview,
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(
                      l.rewardsPreviewName(widget.preview.theme.name.isEmpty ? item.name : widget.preview.theme.name),
                      style: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!owned && item.price != null)
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                          onPressed: _busy ? null : () => _run(c.buyPreview),
                          child: Text(l.rewardsPreviewBuy(item.price!)),
                        ),
                      if (owned && !item.equipped)
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  await c.equipPreview();
                                  return null;
                                }),
                          child: Text(l.rewardsEquip),
                        ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
                        onPressed: _busy ? null : c.stopPreview,
                        child: Text(l.rewardsPreviewStop),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

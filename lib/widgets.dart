/// Small shared pieces, so the three screens look like one app.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';

/// Core link namespace → what a person calls the console. A Wii or DS links
/// from the website by friend code; WFC minted no name for itself, so the
/// family's own is used here.
const platformNames = {
  'switch': 'Switch',
  'wiiu': 'Wii U',
  '3ds': '3DS',
  'wfc': 'Wii / DS',
};

/// A bordered surface: the site's card, which sits on the page rather than
/// floating above it.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    // A Material rather than a decorated box, so a ListTile inside draws its
    // ink on the card instead of under it.
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radiusCard), boxShadow: t.shadow),
      child: Material(
        color: t.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: t.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          // Flexible: a long heading ("Möchte mit dir befreundet sein") at
          // large text wraps rather than pushing its count off the screen.
          Flexible(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                color: t.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: t.accentWeak,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                trailing!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// An initial in a disc, with a presence ring. When [avatarUrl] is
/// provided the image is shown instead of the initial, falling back
/// to the initial on any error.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.online = false,
    this.dim = false,
    this.avatarUrl,
  });
  final String name;
  final bool online;
  final bool dim;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final scheme = Theme.of(context).colorScheme;
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: dim ? t.paper2 : t.accentWeak,
          shape: BoxShape.circle,
          border: Border.all(
            color: online ? t.ok : t.line,
            width: online ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: ClipOval(
          child: Image.network(
            avatarUrl!,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (_, _, __) => Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(
                color: dim ? t.muted : scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : Container(width: 40, height: 40, color: t.paper2),
          ),
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: dim ? t.paper2 : null,
        gradient: dim ? null : avatarGradient,
        shape: BoxShape.circle,
        border: Border.all(
          color: online ? t.ok : t.line,
          width: online ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: dim ? t.muted : Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class ScrollableMessage extends StatelessWidget {
  const ScrollableMessage(this.text, {super.key});
  final String text;

  /// Always a scrollable, so pull-to-refresh still works when there is
  /// nothing to show — which is exactly when someone wants to retry.
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(24, 72 + glassTop(context), 24, 24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: tokensOf(context).muted),
        ),
      ),
    ],
  );
}

/// The failure state every tab shows, with the reason underneath it.
///
/// The reason is not decoration: "could not load" alone cannot tell a dead
/// token from a phone with no route to the server, and both look identical
/// from the sofa.
class LoadFailure extends StatelessWidget {
  const LoadFailure(this.error, {super.key});
  final Object? error;

  static String reasonOf(AppLocalizations l, Object? e) {
    if (e is ApiException) {
      return e.unauthorized ? l.loadSignedOut : l.loadReason(apiErrorText(l, e), e.statusCode);
    }
    final s = e?.toString() ?? '';
    if (s.contains('Failed host lookup') || s.contains('SocketException')) {
      return l.loadNoRoute;
    }
    return s.isEmpty ? '' : s.split('\n').first;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListView(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 72 + glassTop(context), 24, 24),
          child: Column(
            children: [
              Text(
                context.l10n.loadFailed,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted),
              ),
              const SizedBox(height: 8),
              Text(
                reasonOf(context.l10n, error),
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void showToast(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

/// [action] names the confirming button where "Confirm" would be vague.
Future<bool> confirm(BuildContext context, String title, {String? detail, String? action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: detail == null ? null : Text(detail),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action ?? context.l10n.commonConfirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A dialog of a few text fields; the values in order, or null when cancelled.
/// A label starting with '*' is a secret and one starting with '@' an e-mail
/// address; the mark is not shown. (Marked rather than guessed from the words,
/// which are translated.)
Future<List<String>?> promptForm(
  BuildContext context, {
  required String title,
  required List<String> labels,
  required String action,
  List<String> initial = const [],
  String? help,
}) {
  final controllers = [
    for (var i = 0; i < labels.length; i++)
      TextEditingController(text: i < initial.length ? initial[i] : ''),
  ];
  return showDialog<List<String>>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < labels.length; i++)
              TextField(
                controller: controllers[i],
                autofocus: i == 0,
                obscureText: labels[i].startsWith('*'),
                autocorrect: false,
                keyboardType: labels[i].startsWith('@') ? TextInputType.emailAddress : null,
                decoration: InputDecoration(labelText: labels[i].replaceFirst(RegExp('^[*@]'), '')),
              ),
            if (help != null) ...[
              const SizedBox(height: 12),
              Text(help, style: TextStyle(color: tokensOf(context).muted, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, [
            for (var i = 0; i < labels.length; i++)
              labels[i].startsWith('*') ? controllers[i].text : controllers[i].text.trim(),
          ]),
          child: Text(action),
        ),
      ],
    ),
  );
}

Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String hint,
  String? help,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          if (help != null) ...[
            const SizedBox(height: 12),
            Text(
              help,
              style: TextStyle(color: tokensOf(context).muted, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(context.l10n.commonSend),
        ),
      ],
    ),
  );
}

/// Copy something short, and say so with [done]. Used for the friend code,
/// which exists to be given to someone else.
Future<void> copyToClipboard(BuildContext context, String value, String done) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) showToast(context, done);
}

/// An account's avatar: the stored image when there is one, the initial when
/// there is not. avatar_url is null rather than a URL that 404s precisely so
/// this decision can be made without a failed request first.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.api,
    required this.account,
    this.size = 48,
  });
  final OpenPakApi api;
  final Account account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (account.avatarUrl == null) {
      return SizedBox(
        width: size,
        height: size,
        child: FittedBox(child: Avatar(name: account.displayName)),
      );
    }
    return ClipOval(
      child: Image.network(
        api.absolute(account.avatarUrl!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A failed image is not worth an error state: fall back to the same
        // initial the account would have shown with no avatar at all.
        errorBuilder: (_, _, _) => SizedBox(
          width: size,
          height: size,
          child: FittedBox(child: Avatar(name: account.displayName)),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Container(width: size, height: size, color: t.paper2),
      ),
    );
  }
}

/// How a row reads at a glance. The tint carries the state so the pill beside
/// it is free to carry the fact — a player count, a title, a time — instead of
/// repeating what the colour already said. Grey is not a fifth colour for
/// "slightly wrong": it means nothing is being claimed.
///
/// [beta] is the site's indigo: it runs, so it is not "in progress" amber.
enum RowState { ok, beta, warn, bad, idle }

/// One tinted row: name on the left, pill on the right. The same shape as the
/// website's status page and the console link pages, so the three read as one
/// product rather than three things that share a logo.
///
/// [expandedChild] turns the row into a disclosure: a tap reveals it below
/// the header rather than firing [onTap]. Leaving it null keeps every other
/// caller's row exactly as it was — a single line, no chevron.
class StateRow extends StatefulWidget {
  const StateRow({
    super.key,
    required this.name,
    required this.pill,
    this.state = RowState.idle,
    this.leading,
    this.trailing,
    this.onTap,
    this.expandedChild,
  });

  final String name;
  final String pill;
  final RowState state;
  final Widget? leading;

  /// Actions that belong to this row; they sit on a line of their own under it.
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? expandedChild;

  @override
  State<StateRow> createState() => _StateRowState();
}

class _StateRowState extends State<StateRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final expandable = widget.expandedChild != null;
    final (bg, border, ink) = switch (widget.state) {
      RowState.ok => (t.okWeak, t.okLine, t.ok),
      RowState.beta => (t.accentWeak, t.accentLine, Theme.of(context).colorScheme.primary),
      RowState.warn => (t.warnWeak, t.warnLine, t.warn),
      RowState.bad => (t.badWeak, t.badLine, t.bad),
      RowState.idle => (t.raised, t.line, t.muted),
    };
    final hasActions = widget.trailing != null;
    final name = Text(
      widget.name,
      style: const TextStyle(fontWeight: FontWeight.w600),
      overflow: TextOverflow.ellipsis,
    );
    final pill = _Pill(
      text: widget.pill,
      color: ink,
      border: widget.state == RowState.idle ? t.line2 : border,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: expandable ? () => setState(() => _open = !_open) : widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 12)],
                  if (!hasActions) ...[
                    Expanded(child: name),
                    const SizedBox(width: 10),
                    // Align, so the pill sits at the row's end (the site's
                    // margin-left: auto) rather than where the name's half ends.
                    Flexible(child: Align(alignment: Alignment.centerRight, child: pill)),
                  ] else
                    // With actions beside them, a name and a pill in one line
                    // leave each a sliver at 390px; stacked, both read whole.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [name, const SizedBox(height: 6), pill],
                      ),
                    ),
                  if (expandable) ...[
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(Icons.expand_more, size: 20, color: t.muted),
                    ),
                  ],
                ],
              ),
              // Actions wrap under the row, right-aligned, as the site's do.
              if (hasActions)
                Align(alignment: Alignment.centerRight, child: widget.trailing!),
              if (expandable)
                // AnimatedSize rather than AnimatedCrossFade: the latter lays
                // out both children at all times to interpolate between them,
                // which would keep the detail's widgets (and the game icon's
                // network request) alive even while collapsed. This animates
                // the same height change with only one child mounted at a time.
                AnimatedSize(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _open
                      ? Padding(padding: const EdgeInsets.only(top: 12), child: widget.expandedChild!)
                      : const SizedBox(width: double.infinity),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, required this.border});
  final String text;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The dot repeats the state in shape as well as colour, for anyone who
        // cannot rely on the tint alone.
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        // Flexible rather than a bare Text: a pill can now carry a game name
        // instead of a fixed word like "Online", and a long one is truncated
        // rather than pushing the row past its bounds.
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// A paragraph that must be read before acting: the website's amber notice.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.warnWeak,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: t.warnLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: t.warn),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4))),
        ],
      ),
    );
  }
}

/// A state's pill on its own, outside a row: the Verified badge, a legend.
class StatePill extends StatelessWidget {
  const StatePill({super.key, required this.text, required this.state});
  final String text;
  final RowState state;

  @override
  Widget build(BuildContext context) {
    final (bg, border, ink) = stateColors(context, state);
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: _Pill(text: text, color: ink, border: border),
    );
  }
}

/// A state's (background, border, ink), as the site's badge classes.
(Color, Color, Color) stateColors(BuildContext context, RowState state) {
  final t = tokensOf(context);
  return switch (state) {
    RowState.ok => (t.okWeak, t.okLine, t.ok),
    RowState.beta => (t.accentWeak, t.accentLine, Theme.of(context).colorScheme.primary),
    RowState.warn => (t.warnWeak, t.warnLine, t.warn),
    RowState.bad => (t.badWeak, t.badLine, t.bad),
    RowState.idle => (t.paper2, t.line, t.ink2),
  };
}

/// Decline and Accept under a friend request: an outline pill and the
/// primary one, as on the site.
class RequestActions extends StatelessWidget {
  const RequestActions({super.key, required this.onDecline, required this.onAccept});
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    const compact = Size(0, 40);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      // A Wrap: with a long label or large text the two go onto two lines.
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: onDecline,
            style: OutlinedButton.styleFrom(minimumSize: compact),
            child: Text(context.l10n.commonDecline),
          ),
          FilledButton(
            onPressed: onAccept,
            style: FilledButton.styleFrom(minimumSize: compact),
            child: Text(context.l10n.friendsAccept),
          ),
        ],
      ),
    );
  }
}

/// A page list's padding: 20 at the sides, and room for the glass header
/// and tab bar the page scrolls under (their size arrives as MediaQuery
/// padding, which an explicit padding would otherwise ignore).
EdgeInsets pagePadding(BuildContext context, {double top = 8, double bottom = 24}) {
  final mq = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(20, top + mq.top, 20, bottom + mq.bottom);
}

/// The site's glass: what scrolls under it shows through, blurred.
Widget glass(Widget child) => ClipRect(
  child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: child),
);

/// The site's sticky header: the page tint over a blur, a hairline under it.
/// Pair it with extendBodyBehindAppBar and [pagePadding].
AppBar glassAppBar({Widget? title, List<Widget>? actions}) => AppBar(
  title: title,
  actions: actions,
  flexibleSpace: glass(const SizedBox.expand()),
);

/// How far down a page's content starts under the glass header: where a
/// pull-to-refresh spinner should appear from.
double glassTop(BuildContext context) => MediaQuery.paddingOf(context).top;

/// The site's live dot: 8px in the state's colour; online ones wear a halo
/// that pulses outward, unless the system asks for less motion.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, required this.live});
  final bool live;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final still = !widget.live || MediaQuery.disableAnimationsOf(context);
    if (still) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        // 0 → 70% of the cycle the ring grows and fades; the rest it rests.
        final p = still ? 0.0 : (_pulse.value / 0.7).clamp(0.0, 1.0);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.live ? t.ok : t.muted,
            shape: BoxShape.circle,
            boxShadow: [
              if (widget.live) BoxShadow(color: t.okWeak, spreadRadius: 3),
              if (!still) BoxShadow(color: t.ok.withValues(alpha: 0.45 * (1 - p)), spreadRadius: 8 * p),
            ],
          ),
        );
      },
    );
  }
}

/// The site's usage meter: 4px, a sunk track, the indigo-to-violet fill
/// (amber when [warn]).
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.value, this.warn = false});
  final double value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      height: 4,
      decoration: BoxDecoration(color: t.sunk, borderRadius: BorderRadius.circular(999)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: warn ? t.warn : null,
            gradient: warn ? null : const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
          ),
        ),
      ),
    );
  }
}

/// A ListTile's trailing action, capped at 40% of the screen: with large
/// accessibility text a button's label wraps instead of taking the whole
/// row, which ListTile refuses (and the page goes blank). Null stays null.
Widget? tileAction(BuildContext context, Widget? action) => action == null
    ? null
    : ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
        child: action,
      );

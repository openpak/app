/// Small shared pieces, so the three screens look like one app.
library;

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
    return Material(
      color: t.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
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
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: t.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
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
        color: dim ? t.paper2 : t.accentWeak,
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
          color: dim ? t.muted : scheme.primary,
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
        padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
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
          padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
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

Future<bool> confirm(BuildContext context, String title, {String? detail}) async {
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
          child: Text(context.l10n.commonConfirm),
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
enum RowState { ok, warn, bad, idle }

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

  /// An action that belongs to this row, after the pill.
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
      RowState.warn => (t.warnWeak, t.warnLine, t.warn),
      RowState.bad => (t.badWeak, t.badLine, t.bad),
      RowState.idle => (t.raised, t.line, t.muted),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
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
                  Expanded(
                    child: Text(
                      widget.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: _Pill(
                      text: widget.pill,
                      color: ink,
                      border: widget.state == RowState.idle ? t.line2 : border,
                    ),
                  ),
                  if (widget.trailing != null) ...[const SizedBox(width: 4), widget.trailing!],
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
        borderRadius: BorderRadius.circular(12),
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

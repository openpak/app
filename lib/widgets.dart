/// Small shared pieces, so the three screens look like one app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';

import 'theme.dart';

/// A bordered surface: the site's card, which sits on the page rather than
/// floating above it.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.line),
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

/// An initial in a disc, with a presence ring. There are no avatar images in
/// the API yet, so this is the honest version rather than a placeholder face.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.online = false, this.dim = false});
  final String name;
  final bool online;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final scheme = Theme.of(context).colorScheme;
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

  static String reasonOf(Object? e) {
    if (e is ApiException) {
      return e.unauthorized
          ? 'Signed out — sign in again.'
          : '${e.message} (${e.statusCode})';
    }
    final s = e?.toString() ?? '';
    if (s.contains('Failed host lookup') || s.contains('SocketException')) {
      return 'No route to the server from this phone.';
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
                'Could not load. Pull down to try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted),
              ),
              const SizedBox(height: 8),
              Text(
                reasonOf(error),
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return ok ?? false;
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Send'),
        ),
      ],
    ),
  );
}

/// Copy something short, and say so. Used for the friend code, which exists to
/// be given to someone else.
Future<void> copyToClipboard(BuildContext context, String value, String what) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) showToast(context, '$what copied.');
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
class StateRow extends StatelessWidget {
  const StateRow({
    super.key,
    required this.name,
    required this.pill,
    this.state = RowState.idle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String name;
  final String pill;
  final RowState state;
  final Widget? leading;

  /// An action that belongs to this row, after the pill.
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final (bg, border, ink) = switch (state) {
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
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              _Pill(text: pill, color: ink, border: state == RowState.idle ? t.line2 : border),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
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
        Text(
          text,
          style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

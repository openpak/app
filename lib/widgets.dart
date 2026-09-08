/// Small shared pieces, so the three screens look like one app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

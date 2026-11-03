import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'open_url.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Discord row of Linked platforms. Fetched on its own so the Account
/// page never waits for it, and gone altogether while the server has no
/// Discord credentials (as on the website) or cannot say.
class DiscordRow extends StatefulWidget {
  const DiscordRow({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<DiscordRow> createState() => _DiscordRowState();
}

class _DiscordRowState extends State<DiscordRow> {
  DiscordLink? _link; // null: not known (yet), so nothing shows

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await widget.api.discord();
      if (mounted) setState(() => _link = l);
    } catch (_) {
      if (mounted) setState(() => _link = null);
    }
  }

  Future<void> _unlink() async {
    final l = context.l10n;
    if (!await confirm(context, l.discordUnlink, detail: l.discordLinkedHelp, action: l.discordUnlink)) return;
    try {
      await widget.api.unlinkDiscord();
      if (!mounted) return;
      showToast(context, l.discordRemoved);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    if (link == null || (!link.configured && !link.linked)) return const SizedBox.shrink();
    final t = tokensOf(context);
    final l = context.l10n;
    return Column(
      children: [
        const Divider(height: 1),
        if (link.linked)
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: Text(l.discordTitle),
            subtitle: Text(link.username.isEmpty ? l.discordLinkedHelp : link.username),
            trailing: tileAction(
              context,
              TextButton(onPressed: _unlink, child: Text(l.accountUnlink, style: TextStyle(color: t.bad))),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.forum_outlined),
                    const SizedBox(width: 16),
                    Expanded(child: Text(l.discordTitle, style: Theme.of(context).textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l.discordHelp, style: TextStyle(color: t.muted, fontSize: 13)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => openExternalUrl(Uri.parse('${widget.api.baseUrl}/account#devices')),
                  child: Text(l.discordLink),
                ),
                const SizedBox(height: 4),
                Text(l.discordLinkNote, style: TextStyle(color: t.muted, fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Wii U / 3DS row of Linked platforms: the Network ID to type on the console. The OpenPak
/// password is the console password, set whenever the website or this app sees it at sign-in; a
/// separate console password is only the way out for one a Wii U cannot take. Fetched on its
/// own, so the Account page never waits for it.
class ConsolePasswordRow extends StatefulWidget {
  const ConsolePasswordRow({super.key, required this.api, this.twoFactor = false});
  final OpenPakApi api;
  final bool twoFactor;

  @override
  State<ConsolePasswordRow> createState() => _ConsolePasswordRowState();
}

class _ConsolePasswordRowState extends State<ConsolePasswordRow> {
  ConsolePassword? _info; // null: not known (yet), so nothing shows

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final i = await widget.api.consolePassword();
      if (mounted) setState(() => _info = i);
    } catch (_) {
      if (mounted) setState(() => _info = null);
    }
  }

  Future<void> _set() async {
    final l = context.l10n;
    final info = _info!;
    final v = await promptForm(
      context,
      title: l.consoleSet,
      labels: [
        '*${l.consoleNewPassword}',
        '*${l.consoleRepeatPassword}',
        '*${l.commonCurrentPassword}',
        if (widget.twoFactor) l.commonCode,
      ],
      action: l.consoleSet,
      help: l.consoleRules(info.nnid, info.min, info.max),
    );
    if (!mounted || v == null || v[0].isEmpty || v[2].isEmpty) return;
    if (v[0] != v[1]) {
      showToast(context, l.consoleMismatch);
      return;
    }
    try {
      await widget.api.setConsolePassword(v[2], v[0], code: widget.twoFactor ? v[3] : null);
      if (!mounted) return;
      showToast(context, l.consoleSaved);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, switch (e.code ?? e.message) {
        'password_length' || 'password_ascii' || 'password_is_id' => l.consoleRulesBroken,
        'wrong_password' || 'wrong password' => l.errorWrongPassword,
        _ => e.statusCode == 429 ? l.errorTwoFactorLocked : apiErrorText(l, e),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final t = tokensOf(context);
    final l = context.l10n;
    final (text, warn) = switch (info.mode) {
      'sync' => (l.consoleSync(info.nnid), false),
      'custom' => (l.consoleCustom(info.nnid), false),
      'incompatible' => (l.consoleIncompatible(info.nnid), true),
      _ => (l.consoleUnsynced(info.nnid), false),
    };
    return Column(
      children: [
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.sports_esports_outlined),
          title: Text(l.consoleTitle),
          subtitle: Text(text, style: TextStyle(color: warn ? t.warn : t.muted)),
          isThreeLine: true,
          trailing: tileAction(
            context,
            TextButton(onPressed: _set, child: Text(l.consoleSetShort)),
          ),
        ),
      ],
    );
  }
}

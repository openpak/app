import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Where the setup started by POST /me/2fa/setup is finished: the key goes into
/// an authenticator app, its first code switches two-factor on, and the ten
/// recovery codes are shown — once, because the server keeps only hashes.
class TwoFactorSetupPage extends StatefulWidget {
  const TwoFactorSetupPage({super.key, required this.api, required this.secret});
  final OpenPakApi api;
  final TwoFactorSecret secret;

  @override
  State<TwoFactorSetupPage> createState() => _TwoFactorSetupPageState();
}

class _TwoFactorSetupPageState extends State<TwoFactorSetupPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  List<String>? _recoveryCodes;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Most authenticator apps register for otpauth://, so this is the one-tap
  /// path; when none does, the link is copied for pasting instead.
  Future<void> _openInApp() async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(widget.secret.otpauthUri), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: widget.secret.otpauthUri));
    if (mounted) {
      showToast(context, context.l10n.twoFactorLinkCopied);
    }
  }

  Future<void> _enable() async {
    final l = context.l10n;
    if (_code.text.trim().isEmpty) {
      setState(() => _error = l.commonCodeMissing);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codes = await widget.api.twoFactorEnable(_code.text.trim());
      setState(() => _recoveryCodes = codes);
    } on ApiException catch (e) {
      setState(() => _error = switch (e.statusCode) {
        401 => l.errorWrongCode,
        429 => l.errorTwoFactorLocked,
        409 => l.twoFactorChanged,
        _ => apiErrorText(l, e),
      });
    } catch (_) {
      setState(() => _error = l.commonNoConnection);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final codes = _recoveryCodes;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(context.l10n.twoFactorTitle)),
      body: Builder(
        builder: (context) => ListView(
          padding: pagePadding(context, top: 16, bottom: 32),
          children: codes != null ? _done(t, codes) : _setup(t),
        ),
      ),
    );
  }

  List<Widget> _setup(Tokens t) => [
    Text(context.l10n.twoFactorSetupSub, style: TextStyle(color: t.muted)),
    const SizedBox(height: 20),
    SectionLabel(context.l10n.twoFactorKey),
    Panel(
      child: ListTile(
        title: SelectableText(
          widget.secret.secret,
          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, letterSpacing: 1),
        ),
        trailing: IconButton(
          tooltip: context.l10n.commonCopy,
          icon: Icon(Icons.copy_rounded, color: t.muted),
          onPressed: () => copyToClipboard(context, widget.secret.secret, context.l10n.twoFactorKeyCopied),
        ),
      ),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: _openInApp,
      icon: const Icon(Icons.open_in_new),
      label: Text(context.l10n.twoFactorOpenInApp),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: t.line),
      ),
    ),
    const SizedBox(height: 20),
    Notice(context.l10n.twoFactorConsolesWarning),
    const SizedBox(height: 20),
    TextField(
      controller: _code,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
      onSubmitted: (_) => _busy ? null : _enable(),
      decoration: InputDecoration(labelText: context.l10n.twoFactorCodeFromApp, border: const OutlineInputBorder()),
    ),
    if (_error != null) ...[
      const SizedBox(height: 12),
      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ],
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy ? null : _enable,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: _busy
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(context.l10n.twoFactorTurnOn),
    ),
  ];

  List<Widget> _done(Tokens t, List<String> codes) => [
    StateRow(name: context.l10n.twoFactorIsOn, pill: context.l10n.twoFactorOnPill, state: RowState.ok),
    const SizedBox(height: 12),
    SectionLabel(context.l10n.twoFactorRecoveryCodes, trailing: '${codes.length}'),
    Text(context.l10n.twoFactorRecoveryCodesSub, style: TextStyle(color: t.muted)),
    const SizedBox(height: 12),
    Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          codes.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 15, height: 1.6),
        ),
      ),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: () => copyToClipboard(context, codes.join('\n'), context.l10n.twoFactorRecoveryCodesCopied),
      icon: const Icon(Icons.copy_rounded),
      label: Text(context.l10n.commonCopy),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: t.line),
      ),
    ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: () => Navigator.pop(context, true),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Text(context.l10n.twoFactorSaved),
    ),
  ];
}

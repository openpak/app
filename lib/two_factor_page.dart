import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Said before two-factor is switched on, as the website says it: consoles
/// sign in with the password alone and cannot be asked for a code yet.
const consolesWarning =
    'Consoles that sign in with your password (Switch, Wii U and 3DS) cannot ask '
    'for a code yet. With two-factor on, those consoles can no longer sign in '
    'with your password until they support it.';

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
      showToast(context, 'No authenticator app opened it, so the link is copied. Paste it into your app.');
    }
  }

  Future<void> _enable() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Type the code from your app.');
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
        401 => 'That code is not right. Check the time on your phone and try the newest code.',
        429 => 'Too many wrong codes. Try again in 15 minutes.',
        409 => 'Two-factor changed in the meantime. Go back and try again.',
        _ => e.message,
      });
    } catch (_) {
      setState(() => _error = 'Could not reach OpenPak. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final codes = _recoveryCodes;
    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor authentication')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: codes != null ? _done(t, codes) : _setup(t),
      ),
    );
  }

  List<Widget> _setup(Tokens t) => [
    Text(
      'Add this key to an authenticator app, then type the code it shows to switch two-factor on.',
      style: TextStyle(color: t.muted),
    ),
    const SizedBox(height: 20),
    const SectionLabel('Key'),
    Panel(
      child: ListTile(
        title: SelectableText(
          widget.secret.secret,
          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, letterSpacing: 1),
        ),
        trailing: IconButton(
          tooltip: 'Copy',
          icon: Icon(Icons.copy_rounded, color: t.muted),
          onPressed: () => copyToClipboard(context, widget.secret.secret, 'Key'),
        ),
      ),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: _openInApp,
      icon: const Icon(Icons.open_in_new),
      label: const Text('Open in an authenticator app'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: t.line),
      ),
    ),
    const SizedBox(height: 20),
    const Notice(consolesWarning),
    const SizedBox(height: 20),
    TextField(
      controller: _code,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
      onSubmitted: (_) => _busy ? null : _enable(),
      decoration: const InputDecoration(labelText: 'Code from the app', border: OutlineInputBorder()),
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
          : const Text('Turn on two-factor'),
    ),
  ];

  List<Widget> _done(Tokens t, List<String> codes) => [
    const StateRow(name: 'Two-factor authentication is on.', pill: 'On', state: RowState.ok),
    const SizedBox(height: 12),
    SectionLabel('Recovery codes', trailing: '${codes.length}'),
    Text(
      'Each one signs you in once if you lose your phone. Save them somewhere safe now: '
      'they are not shown again.',
      style: TextStyle(color: t.muted),
    ),
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
      onPressed: () => copyToClipboard(context, codes.join('\n'), 'Recovery codes'),
      icon: const Icon(Icons.copy_rounded),
      label: const Text('Copy'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: t.line),
      ),
    ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: () => Navigator.pop(context, true),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: const Text('I have saved them'),
    ),
  ];
}

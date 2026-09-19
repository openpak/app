import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'logo.dart';
import 'widgets.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.api, required this.onSignedIn});
  final OpenPakApi api;
  final Future<void> Function(String token) onSignedIn;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Set once the password was right and the account wants a second factor.
  /// The form then asks for the code alone; the password stays filled in, so
  /// starting again is one tap.
  String? _challenge;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startAgain({String? error}) => setState(() {
    _challenge = null;
    _code.clear();
    _error = error;
  });

  Future<void> _submitCode() async {
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
      final token = await widget.api.signInSecondFactor(_challenge!, _code.text);
      await widget.onSignedIn(token);
    } on ApiException catch (e) {
      // A 401 cannot tell a wrong code from a spent challenge, and a spent one
      // cannot be retried, so both go back to the password.
      if (e.unauthorized) {
        _startAgain(error: l.signInCodeWrong);
      } else {
        setState(() => _error = e.statusCode == 429 ? l.errorTwoFactorLocked : apiErrorText(l, e));
      }
    } catch (_) {
      setState(() => _error = l.commonNoConnection);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final l = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await widget.api.signIn(
        _email.text.trim(),
        _password.text,
      );
      await widget.onSignedIn(token);
    } on TwoFactorRequired catch (c) {
      setState(() => _challenge = c.challenge);
    } on ApiException catch (e) {
      // The server distinguishes wrong credentials from being rate limited,
      // and so should the message: one is worth retrying immediately.
      setState(() => _error = e.statusCode == 429
          ? l.errorRateLimited
          : e.unauthorized
          ? l.errorInvalidCredentials
          : apiErrorText(l, e));
    } catch (_) {
      setState(() => _error = l.commonNoConnection);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Both answers are the same whether or not the address has an account, so
  /// the message only says what to look for.
  Future<void> _forgot() async {
    final l = context.l10n;
    final v = await promptForm(
      context,
      title: l.signInResetTitle,
      labels: ['@${l.commonEmail}'],
      initial: [_email.text.trim()],
      action: l.commonSend,
      help: l.signInResetHelp,
    );
    if (v == null || v[0].isEmpty) return;
    await _ask(() => widget.api.forgotPassword(v[0]), l.signInResetSent);
  }

  Future<void> _register() async {
    final l = context.l10n;
    final v = await promptForm(
      context,
      title: l.signInCreateAccount,
      labels: [l.commonDisplayName, '@${l.commonEmail}', '*${l.commonPassword}'],
      action: l.signInCreate,
      help: l.signInCreateHelp,
    );
    if (v == null) return;
    await _ask(
      () => widget.api.register(displayName: v[0], email: v[1], password: v[2]),
      l.signInCreateSent(v[1]),
    );
  }

  Future<void> _ask(Future<void> Function() call, String done) async {
    final l = context.l10n;
    try {
      await call();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.statusCode == 429 ? l.errorRateLimited : apiErrorText(l, e));
    } catch (_) {
      if (mounted) showToast(context, l.commonNoConnection);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: OpenPakLogo(size: 88)),
                  const SizedBox(height: 20),
                  Text(
                    'OpenPak',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (_challenge != null) ..._codeStep(context) else ..._passwordStep(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The second step, as the website's: one field for either kind of code.
  List<Widget> _codeStep(BuildContext context) => [
    Text(context.l10n.signInCodeTitle, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
    const SizedBox(height: 4),
    Text(context.l10n.signInCodeSub, textAlign: TextAlign.center),
    const SizedBox(height: 20),
    TextField(
      controller: _code,
      autofocus: true,
      autocorrect: false,
      autofillHints: const [AutofillHints.oneTimeCode],
      onSubmitted: (_) => _busy ? null : _submitCode(),
      decoration: InputDecoration(
        labelText: context.l10n.commonCode,
        helperText: context.l10n.commonCodeHelp,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    ),
    ..._errorLine(context),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _busy ? null : _submitCode,
      child: _busy ? _spinner : Text(context.l10n.signInButton),
    ),
    const SizedBox(height: 8),
    TextButton(onPressed: _busy ? null : _startAgain, child: Text(context.l10n.signInStartAgain)),
  ];

  static const _spinner = SizedBox(
    height: 20,
    width: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  List<Widget> _errorLine(BuildContext context) => [
    if (_error != null) ...[
      const SizedBox(height: 16),
      Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ],
  ];

  List<Widget> _passwordStep(BuildContext context) => [
    TextField(
      controller: _email,
      autofillHints: const [AutofillHints.email],
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: context.l10n.commonEmail,
        border: const OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _password,
      autofillHints: const [AutofillHints.password],
      obscureText: true,
      onSubmitted: (_) => _busy ? null : _submit(),
      decoration: InputDecoration(
        labelText: context.l10n.commonPassword,
        border: const OutlineInputBorder(),
      ),
    ),
    ..._errorLine(context),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _busy ? null : _submit,
      child: _busy ? _spinner : Text(context.l10n.signInButton),
    ),
    const SizedBox(height: 8),
    Wrap(
      alignment: WrapAlignment.spaceBetween,
      children: [
        TextButton(onPressed: _forgot, child: Text(context.l10n.signInForgot)),
        TextButton(onPressed: _register, child: Text(context.l10n.signInCreateAccount)),
      ],
    ),
  ];
}

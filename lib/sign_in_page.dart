import 'package:flutter/material.dart';

import 'api.dart';
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
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
    } on ApiException catch (e) {
      // The server distinguishes wrong credentials from being rate limited,
      // and so should the message: one is worth retrying immediately.
      setState(() => _error = e.statusCode == 429
          ? 'Too many attempts. Wait a minute and try again.'
          : e.unauthorized
          ? 'That e-mail and password do not match.'
          : e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach OpenPak. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Both answers are the same whether or not the address has an account, so
  /// the message only says what to look for.
  Future<void> _forgot() async {
    final v = await promptForm(
      context,
      title: 'Reset your password',
      labels: const ['E-mail'],
      initial: [_email.text.trim()],
      action: 'Send',
      help: 'A link to set a new one comes by mail.',
    );
    if (v == null || v[0].isEmpty) return;
    await _ask(() => widget.api.forgotPassword(v[0]), 'If that address has an account, a reset mail is on its way.');
  }

  Future<void> _register() async {
    final v = await promptForm(
      context,
      title: 'Create an account',
      labels: const ['Display name', 'E-mail', '*Password'],
      action: 'Create',
      help: 'At least 8 characters for the password. You verify the address before signing in.',
    );
    if (v == null) return;
    await _ask(
      () => widget.api.register(displayName: v[0], email: v[1], password: v[2]),
      'Check ${v[1]} for a mail to verify it, then sign in.',
    );
  }

  Future<void> _ask(Future<void> Function() call, String done) async {
    try {
      await call();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.statusCode == 429 ? 'Too many attempts. Wait a minute and try again.' : e.message);
    } catch (_) {
      if (mounted) showToast(context, 'Could not reach OpenPak. Check your connection.');
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
                  TextField(
                    controller: _email,
                    autofillHints: const [AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    autofillHints: const [AutofillHints.password],
                    obscureText: true,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
                      TextButton(onPressed: _register, child: const Text('Create an account')),
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

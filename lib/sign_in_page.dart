import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'logo.dart';
import 'theme.dart';
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
    final v = await showDialog<_Signup>(context: context, builder: (_) => const _RegisterDialog());
    if (v == null) return;
    await _ask(
      () => widget.api.register(
        handle: v.handle,
        displayName: v.displayName,
        email: v.email,
        password: v.password,
        birthday: v.birthday,
      ),
      l.signInCreateSent(v.email),
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

/// The youngest age that may sign up. The website enforces it (WEBSITE_MIN_AGE);
/// the app checks first only so the person is told before sending anything.
const minimumAge = 16;

/// Whether someone born on [birthday] is under [minimumAge] on [today]. Someone
/// born on 29 February turns a year older on 1 March, as on the website.
bool underMinimumAge(DateTime birthday, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  return DateTime(birthday.year + minimumAge, birthday.month, birthday.day).isAfter(day);
}

/// YYYY-MM-DD, the format /register takes.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

typedef _Signup = ({String handle, String displayName, String email, String password, String birthday});

/// The create-account dialog: the text fields and a date of birth from a date
/// picker. Under [minimumAge] it says so and will not create the account.
class _RegisterDialog extends StatefulWidget {
  const _RegisterDialog();

  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  final _handle = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  DateTime? _birthday;

  @override
  void dispose() {
    for (final c in [_handle, _name, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: context.l10n.signInBirthday,
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final b = _birthday;
    final tooYoung = b != null && underMinimumAge(b, DateTime.now());
    InputDecoration label(String text) => InputDecoration(labelText: text);
    return AlertDialog(
      title: Text(l.signInCreateAccount),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _handle, autofocus: true, autocorrect: false, decoration: label(l.commonHandle)),
            TextField(controller: _name, autocorrect: false, decoration: label(l.commonDisplayName)),
            TextField(
              controller: _email,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              decoration: label(l.commonEmail),
            ),
            TextField(controller: _password, obscureText: true, autocorrect: false, decoration: label(l.commonPassword)),
            const SizedBox(height: 8),
            InkWell(
              key: const Key('register-birthday'),
              onTap: _pickBirthday,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l.signInBirthday,
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  errorText: tooYoung ? l.signInTooYoung(minimumAge) : null,
                  errorMaxLines: 3,
                ),
                child: Text(b == null ? l.signInBirthdayChoose : shortDate(l, b)),
              ),
            ),
            const SizedBox(height: 12),
            Text(l.handleRules, style: TextStyle(color: Theme.of(context).extension<Tokens>()?.muted, fontSize: 13)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(
          onPressed: b == null || tooYoung
              ? null
              : () => Navigator.pop<_Signup>(context, (
                  handle: _handle.text.trim(),
                  displayName: _name.text.trim(),
                  email: _email.text.trim(),
                  password: _password.text,
                  birthday: isoDay(b),
                )),
          child: Text(l.signInCreate),
        ),
      ],
    );
  }
}

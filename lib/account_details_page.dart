import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Editing the account: avatar, name, country, date of birth.
///
/// Each field saves on its own. A single "save everything" button would make
/// one rejected value discard three good edits, and the API takes them
/// separately for exactly that reason.
class AccountDetailsPage extends StatefulWidget {
  const AccountDetailsPage({super.key, required this.api, required this.account});
  final OpenPakApi api;
  final Account account;

  @override
  State<AccountDetailsPage> createState() => _AccountDetailsPageState();
}

class _AccountDetailsPageState extends State<AccountDetailsPage> {
  late Account _me = widget.account;
  late final _name = TextEditingController(text: _me.displayName);
  bool _dirty = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final me = await widget.api.me();
      if (mounted) setState(() => _me = me);
    } on ApiException {
      // The screen already shows what it had; a failed refresh is not worth
      // replacing it with an error.
    }
  }

  Future<void> _save(Future<void> Function() action, String done) async {
    try {
      await action();
      _dirty = true;
      await _reload();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      // The server says which field and why; repeating it is more use than
      // "could not save".
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _dirty);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Account details')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Center(
              child: Column(
                children: [
                  AccountAvatar(api: widget.api, account: _me, size: 96),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.palette_outlined, size: 18),
                    label: const Text('Change avatar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const SectionLabel('Display name'),
            Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      maxLength: 32,
                      decoration: const InputDecoration(
                        hintText: 'What other people see',
                      ),
                    ),
                    Text(
                      '3 to 32 characters.',
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _save(
                        () => widget.api.updateProfile(
                          displayName: _name.text.trim(),
                        ),
                        'Name saved.',
                      ),
                      child: const Text('Save name'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel('Country'),
            Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      // Not decoration: the console reads it, and an account
                      // that holds nothing sends nothing.
                      'Your console sends this with your profile.',
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _me.country.isEmpty ? null : _me.country,
                      hint: const Text('Not set'),
                      items: [
                        for (final c in countries)
                          DropdownMenuItem(value: c.$1, child: Text(c.$2)),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          _save(
                            () => widget.api.updateProfile(country: v),
                            'Country saved.',
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel('Date of birth'),
            Panel(
              child: ListTile(
                title: Text(_me.birthday.isEmpty ? 'Not set' : _me.birthday),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickBirthday,
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel('Friend code'),
            Panel(
              child: ListTile(
                title: Text(_me.friendCode ?? 'No console linked yet'),
                subtitle: _me.friendCode == null
                    ? null
                    : const Text('Tap to copy'),
                trailing: _me.friendCode == null
                    ? null
                    : const Icon(Icons.copy_rounded, size: 18),
                onTap: _me.friendCode == null
                    ? null
                    : () => copyToClipboard(
                        context,
                        _me.friendCode!,
                        'Friend code',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_me.birthday);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      // No date in the future, the same rule the sign-up form uses.
      lastDate: now,
    );
    if (picked == null) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    await _save(
      () => widget.api.updateProfile(birthday: iso),
      'Date of birth saved.',
    );
  }

  Future<void> _pickAvatar() async {
    final List<AvatarChoice> choices;
    try {
      choices = await widget.api.avatarChoices();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
      return;
    }
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Choose an avatar'),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (final c in choices)
                    InkWell(
                      onTap: () => Navigator.pop(context, c.id),
                      borderRadius: BorderRadius.circular(999),
                      child: ClipOval(
                        child: Image.network(
                          widget.api.absolute(c.url),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Colors.black12),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Uploading your own picture is on the website.',
                style: TextStyle(color: tokensOf(context).muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    await _save(() => widget.api.chooseAvatar(chosen), 'Avatar saved.');
  }
}

/// The ISO codes the site offers, kept short: the console cares about the code,
/// and a full list belongs behind a search field rather than in a dropdown.
const countries = <(String, String)>[
  ('IE', 'Ireland'),
  ('GB', 'United Kingdom'),
  ('US', 'United States'),
  ('CA', 'Canada'),
  ('AU', 'Australia'),
  ('NZ', 'New Zealand'),
  ('FR', 'France'),
  ('DE', 'Germany'),
  ('ES', 'Spain'),
  ('IT', 'Italy'),
  ('PT', 'Portugal'),
  ('NL', 'Netherlands'),
  ('BE', 'Belgium'),
  ('SE', 'Sweden'),
  ('NO', 'Norway'),
  ('DK', 'Denmark'),
  ('FI', 'Finland'),
  ('PL', 'Poland'),
  ('BR', 'Brazil'),
  ('MX', 'Mexico'),
  ('JP', 'Japan'),
];

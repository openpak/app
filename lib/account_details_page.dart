import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'l10n.dart';
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
    final l = context.l10n;
    try {
      await action();
      _dirty = true;
      await _reload();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      // The error code says which field and why; that is more use than
      // "could not save".
      if (mounted) showToast(context, apiErrorText(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _dirty);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.detailsTitle)),
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
                    label: Text(l.detailsChangeAvatar),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SectionLabel(l.commonDisplayName),
            Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      maxLength: 32,
                      decoration: InputDecoration(hintText: l.detailsNameHint),
                    ),
                    Text(
                      l.detailsNameRule,
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _save(
                        () => widget.api.updateProfile(
                          displayName: _name.text.trim(),
                        ),
                        l.detailsNameSaved,
                      ),
                      child: Text(l.detailsSaveName),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SectionLabel(l.detailsCountry),
            Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      // Not decoration: the console reads it, and an account
                      // that holds nothing sends nothing.
                      l.detailsCountryWhy,
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _me.country.isEmpty ? null : _me.country,
                      hint: Text(l.detailsNotSet),
                      items: [
                        for (final c in countries)
                          DropdownMenuItem(value: c, child: Text(countryName(l, c))),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          _save(
                            () => widget.api.updateProfile(country: v),
                            l.detailsCountrySaved,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SectionLabel(l.detailsBirthday),
            Panel(
              child: ListTile(
                title: Text(_me.birthday.isEmpty ? l.detailsNotSet : _me.birthday),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickBirthday,
              ),
            ),
            const SizedBox(height: 20),
            SectionLabel(l.commonFriendCode),
            Panel(
              child: ListTile(
                title: Text(_me.friendCode ?? l.detailsNoConsole),
                subtitle: _me.friendCode == null
                    ? null
                    : Text(l.detailsTapToCopy),
                trailing: _me.friendCode == null
                    ? null
                    : const Icon(Icons.copy_rounded, size: 18),
                onTap: _me.friendCode == null
                    ? null
                    : () => copyToClipboard(
                        context,
                        _me.friendCode!,
                        l.commonFriendCodeCopied,
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
    if (!mounted) return;
    await _save(
      () => widget.api.updateProfile(birthday: iso),
      context.l10n.detailsBirthdaySaved,
    );
  }

  Future<void> _pickAvatar() async {
    final l = context.l10n;
    final List<AvatarChoice> choices;
    try {
      choices = await widget.api.avatarChoices();
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
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
              SectionLabel(l.detailsChooseAvatar),
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
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, _photo),
                icon: const Icon(Icons.photo_outlined),
                label: Text(l.detailsUploadPhoto),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    if (chosen == _photo) return _uploadPhoto();
    await _save(() => widget.api.chooseAvatar(chosen), l.detailsAvatarSaved);
  }

  static const _photo = '\u0000photo'; // the sheet's answer for "Upload a photo"

  /// The server takes a PNG or JPEG of up to 4 MiB; asking the picker for a
  /// scaled JPEG keeps a phone photo well inside that.
  Future<void> _uploadPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _save(() => widget.api.uploadAvatar(bytes, file.name), context.l10n.detailsAvatarSaved);
  }
}

/// The ISO codes the site offers, kept short: the console cares about the code,
/// and a full list belongs behind a search field rather than in a dropdown.
const countries = ['IE', 'GB', 'US', 'CA', 'AU', 'NZ', 'FR', 'DE', 'ES', 'IT', 'PT',
    'NL', 'BE', 'SE', 'NO', 'DK', 'FI', 'PL', 'BR', 'MX', 'JP'];

/// A country's name in the app's language.
String countryName(AppLocalizations l, String code) => switch (code) {
  'IE' => l.countryIe,
  'GB' => l.countryGb,
  'US' => l.countryUs,
  'CA' => l.countryCa,
  'AU' => l.countryAu,
  'NZ' => l.countryNz,
  'FR' => l.countryFr,
  'DE' => l.countryDe,
  'ES' => l.countryEs,
  'IT' => l.countryIt,
  'PT' => l.countryPt,
  'NL' => l.countryNl,
  'BE' => l.countryBe,
  'SE' => l.countrySe,
  'NO' => l.countryNo,
  'DK' => l.countryDk,
  'FI' => l.countryFi,
  'PL' => l.countryPl,
  'BR' => l.countryBr,
  'MX' => l.countryMx,
  'JP' => l.countryJp,
  _ => code,
};

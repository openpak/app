import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'l10n.dart';
import 'parental_editor_page.dart';
import 'parental_lock.dart';
import 'theme.dart';
import 'widgets.dart';

/// One paired console: what it is set to, who plays on it, its PIN and what
/// was played. The setting is shown as the console is served it, in the order
/// the website's page uses; changes go through the editor and are never shown
/// as applied until the console's receipt says so.
class ParentalConsolePage extends StatefulWidget {
  const ParentalConsolePage({super.key, required this.api, required this.device, this.lock});
  final OpenPakApi api;
  final ParentalDevice device;

  /// Asked again before a PIN is set: the one change that can lock a parent
  /// out of their own console.
  final ParentalLock? lock;

  @override
  State<ParentalConsolePage> createState() => _ParentalConsolePageState();
}

class _ParentalConsolePageState extends State<ParentalConsolePage> {
  late ParentalDevice _device = widget.device;
  late final ParentalLock _lock = widget.lock ?? ParentalLock();
  final _images = <String, Future<Uint8List?>>{};
  late Future<List<PlayDay>> _activity = _loadActivity();
  late final AppLifecycleListener _life;

  /// The PIN lives here and on screen, nowhere else: not on disk, not in a
  /// log. It goes whenever the app stops being in front and with the screen.
  String? _pin;
  bool _noPin = false;
  bool _fetchingPin = false;

  /// A PIN was set from here: until the console syncs, its old one still
  /// works, and the screen says so.
  bool _pinSet = false;

  /// Bumped on every hide, so a PIN that arrives after one is dropped.
  int _hides = 0;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onStateChange: (s) {
        if (s != AppLifecycleState.resumed) _hidePin();
      },
    );
  }

  @override
  void dispose() {
    _life.dispose();
    _pin = null;
    super.dispose();
  }

  void _hidePin() {
    _hides++;
    if (_pin != null || _noPin) {
      setState(() {
        _pin = null;
        _noPin = false;
      });
    }
  }

  Future<void> _showPin() async {
    final l = context.l10n;
    final hides = _hides;
    setState(() => _fetchingPin = true);
    try {
      final pin = await widget.api.parentalPin(_device.moonId);
      // A 404 is either "no PIN yet" or "no such console"; the list tells which.
      if (pin == null && !await _refresh()) return;
      if (!mounted || hides != _hides) return;
      setState(() {
        _pin = pin;
        _noPin = pin == null;
      });
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    } catch (_) {
      // Anything else (a body that will not parse) could carry the PIN in its
      // message, so it is not rethrown to the crash reporter.
      if (mounted) showToast(context, l.loadFailed);
    } finally {
      if (mounted) setState(() => _fetchingPin = false);
    }
  }

  /// Fetches the console again; false, having left the screen, when it is no
  /// longer paired to this account.
  Future<bool> _refresh() async {
    final l = context.l10n;
    try {
      final all = await widget.api.parentalDevices();
      if (!mounted) return false;
      final d = all.where((d) => d.paired && d.moonId == _device.moonId).firstOrNull;
      if (d == null) {
        showToast(context, l.parentalConsoleGone);
        Navigator.pop(context);
        return false;
      }
      setState(() {
        _device = d;
        _activity = _loadActivity();
      });
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    }
    return true;
  }

  /// Play time is extra: a failure to load it reads as none rather than as
  /// an error over the rest of the screen.
  Future<List<PlayDay>> _loadActivity() =>
      widget.api.parentalActivity(widget.device.moonId).catchError((Object _) => const <PlayDay>[]);

  /// The editor starts from the document as it is now, not as it was when
  /// this screen opened, so a change made on the website meanwhile is kept.
  Future<void> _edit() async {
    if (!await _refresh() || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ParentalEditorPage(api: widget.api, device: _device)),
    );
    if (saved == null || !mounted) return;
    if (saved) showToast(context, context.l10n.parentalSaved);
    await _refresh();
  }

  Future<void> _changePin() async {
    final l = context.l10n;
    final outcome = await askParentalUnlock(context, widget.api, _lock, l.parentalPinLockReason);
    if (!mounted) return;
    if (outcome != LockOutcome.allowed) {
      if (outcome == LockOutcome.noLockScreen) showToast(context, l.parentalNoScreenLock);
      return;
    }
    final pin = await showDialog<String>(context: context, builder: (_) => const NewPinDialog());
    if (pin == null || !mounted) return;
    try {
      await widget.api.parentalSetPin(_device.moonId, pin);
      if (!mounted) return;
      _hides++;
      setState(() {
        _pin = pin;
        _noPin = false;
        _pinSet = true;
      });
      showToast(context, l.parentalPinSaved);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode != 404) {
        showToast(context, apiErrorText(l, e));
        return;
      }
    } catch (_) {
      // As with showing it: nothing that might carry the PIN reaches the
      // crash reporter.
      if (mounted) showToast(context, l.loadFailed);
      return;
    }
    // Also how a 404 (the console gone) leaves the screen.
    await _refresh();
  }

  Future<void> _rename() async {
    final saved = await renameConsole(context, widget.api, _device);
    if (saved == null || !mounted) return;
    // A false is the console gone; the refresh is what leaves the screen.
    await _refresh();
  }

  Future<void> _remove() async {
    final l = context.l10n;
    if (!await confirm(context, l.parentalRemoveConfirm, detail: l.parentalRemoveDetail, action: l.parentalRemove)) {
      return;
    }
    try {
      await widget.api.parentalRemove(_device.moonId);
    } on ApiException catch (e) {
      // Already gone is what was asked for.
      if (e.statusCode != 404) {
        if (mounted) showToast(context, apiErrorText(l, e));
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    final d = _device;
    final name = d.nickname.isEmpty ? l.parentalConsole : d.nickname;
    final restrictions = _restrictions(context, d.setting);
    final scheme = Theme.of(context).colorScheme;
    // Only a document the server sends whole can be edited: an older
    // server's list has none to start from.
    final editable = d.setting['functionalRestrictionLevel'] is String;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(
        title: Text(name),
        actions: [
          IconButton(tooltip: l.parentalRename, icon: const Icon(Icons.edit_outlined), onPressed: _rename),
        ],
      ),
      // A Builder, so the padding is read below the Scaffold: with
      // extendBodyBehindAppBar the Scaffold's MediaQuery counts the app bar in
      // its top padding, and this page's own context, above it, only the
      // status bar. Read from there, the first panel sat under the bar.
      body: Builder(
        builder: (context) => RefreshIndicator(
          edgeOffset: glassTop(context),
          onRefresh: _refresh,
          child: ListView(
            padding: pagePadding(context),
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        d.syncedAt == null ? l.parentalNotSynced : l.parentalLastSynced(shortDateTime(l, d.syncedAt!)),
                        style: TextStyle(color: t.muted),
                      ),
                      trailing: tileAction(context, switch (d.synced) {
                        true => StatePill(text: l.parentalUpToDate, state: RowState.ok),
                        false => StatePill(text: l.parentalWaitingForConsole, state: RowState.warn),
                        null => null,
                      }),
                    ),
                    // What the console reported of itself, to tell two apart.
                    if (d.serialNumber.isNotEmpty || d.firmware.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          [
                            if (d.serialNumber.isNotEmpty) l.parentalSerial(d.serialNumber),
                            if (d.firmware.isNotEmpty) l.parentalFirmware(d.firmware),
                          ].join(' · '),
                          style: TextStyle(color: t.muted, fontSize: 12),
                        ),
                      ),
                    // Until the console fetches, a change is only on the server.
                    if (d.synced == false)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(l.parentalSyncHelp, style: TextStyle(color: t.muted, fontSize: 13)),
                      ),
                  ],
                ),
              ),
              if (restrictions.isNotEmpty || editable) ...[
                const SizedBox(height: 16),
                SectionLabel(l.parentalRestrictions),
                // Every row opens the editor, and the panel ends in a row that
                // says so: a lone "Restriction level: None" must not read as all
                // there is.
                Panel(
                  child: Column(
                    children: [
                      for (var i = 0; i < restrictions.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          title: Text(restrictions[i].$1),
                          trailing: tileAction(
                            context,
                            Text(restrictions[i].$2, textAlign: TextAlign.end, style: TextStyle(color: t.muted)),
                          ),
                          onTap: editable ? _edit : null,
                        ),
                      ],
                      if (editable) ...[
                        if (restrictions.isNotEmpty) const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.tune, color: scheme.primary),
                          title: Text(
                            l.parentalChangeRestrictions,
                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _edit,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SectionLabel(l.parentalPlayers, trailing: '${d.players.length}'),
              Panel(
                child: d.players.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l.parentalNoPlayers, style: TextStyle(color: t.muted)),
                      )
                    : Column(
                        children: [
                          for (final p in d.players)
                            ListTile(
                              leading: _PlayerImage(
                                name: p.nickname,
                                image: _images.putIfAbsent(p.id, () => widget.api.parentalPlayerImage(d.moonId, p.id)),
                              ),
                              title: Text(p.nickname),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              SectionLabel(l.parentalPinLabel),
              // As dense as the panels above it: the PIN and what it is, then
              // its two actions in one row under a rule.
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: _noPin
                          ? Text(l.parentalPinNone)
                          : Text(
                              // Four dots whatever the length, so the mask does
                              // not tell anyone how long the PIN is.
                              _pin ?? '••••',
                              style: const TextStyle(
                                fontSize: 26,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                                letterSpacing: 8,
                              ),
                            ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(l.parentalPinHelp, style: TextStyle(color: t.muted, fontSize: 13)),
                      ),
                    ),
                    if (_pinSet && d.synced != true)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Notice(l.parentalPinOldStillWorks),
                      ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: OverflowBar(
                        alignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: _fetchingPin ? null : (_pin == null ? _showPin : _hidePin),
                            icon: Icon(_pin == null ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            label: Text(_pin == null ? l.parentalShowPin : l.parentalHidePin),
                          ),
                          TextButton.icon(
                            onPressed: _changePin,
                            icon: const Icon(Icons.password),
                            label: Text(l.parentalChangePin),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Nothing at all when there are none: an empty list here would
              // only read as something to worry about.
              if (d.wrongPinAttempts.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionLabel(l.parentalWrongPin, trailing: '${d.wrongPinAttempts.length}'),
                Panel(
                  child: Column(
                    children: [
                      for (final at in d.wrongPinAttempts)
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.pin_outlined, color: t.warn),
                          title: Text(shortDateTime(l, at)),
                        ),
                    ],
                  ),
                ),
              ],
              FutureBuilder<List<PlayDay>>(
                future: _activity,
                builder: (context, snap) => snap.hasData ? _Activity(days: snap.data!) : const SizedBox.shrink(),
              ),
              const SizedBox(height: 28),
              TextButton.icon(
                onPressed: _remove,
                icon: const Icon(Icons.delete_outline),
                label: Text(l.parentalRemoveConsole),
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: t.bad),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The last days' play, per day and per title. Always its own section, so
/// the feature can be found; one line when nothing was played.
class _Activity extends StatelessWidget {
  const _Activity({required this.days});
  final List<PlayDay> days;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    final played = days.where((d) => d.totalMinutes > 0).toList(growable: false);
    String date(String s) => switch (DateTime.tryParse(s)) {
      final d? => DateFormat.MMMEd(l.localeName).format(d),
      null => s,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        SectionLabel(l.parentalActivity, trailing: l.parentalLast7Days),
        Panel(
          child: Column(
            children: [
              if (played.isEmpty)
                ListTile(title: Text(l.parentalNoActivity, style: TextStyle(color: t.muted))),
              for (var i = 0; i < played.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                // The console's own count, HOME menu included: it can be
                // more than the titles under it add up to, and a day can have
                // no titles at all. Neither is an error.
                ListTile(
                  title: Text(date(played[i].date), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(l.parentalTimeUsed, style: TextStyle(color: t.muted)),
                  trailing: Text(l.parentalMinutes(played[i].totalMinutes)),
                ),
                for (final title in played[i].titles)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 32, right: 16),
                    title: Text(title.name.isEmpty ? title.titleId : title.name),
                    trailing: Text(l.parentalMinutes(title.minutes), style: TextStyle(color: t.muted)),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks for a new name for [device] and saves it: true once saved (and said
/// so), false when the console turned out to be gone, null when cancelled.
Future<bool?> renameConsole(BuildContext context, OpenPakApi api, ParentalDevice device) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => RenameConsoleDialog(api: api, device: device),
  );
  if (saved == true && context.mounted) showToast(context, context.l10n.parentalNameSaved);
  return saved;
}

/// The parent's name for a console. Prefilled only with a name the parent
/// chose, not with the one made from the serial number, so saving it
/// unchanged cannot turn a default into a chosen name. It saves from here, so
/// a refusal lands on the field rather than in a toast behind the dialog.
class RenameConsoleDialog extends StatefulWidget {
  const RenameConsoleDialog({super.key, required this.api, required this.device});
  final OpenPakApi api;
  final ParentalDevice device;

  static const maxLength = 32;

  @override
  State<RenameConsoleDialog> createState() => _RenameConsoleDialogState();
}

class _RenameConsoleDialogState extends State<RenameConsoleDialog> {
  late final String _initial = widget.device.named ? widget.device.nickname : '';
  late final _name = TextEditingController(text: _initial);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.parentalRename(widget.device.moonId, _name.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) return Navigator.pop(context, false);
      setState(() => _error = e.code == 'invalid_name' ? l.parentalNameInvalid : apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final changed = _name.text.trim() != _initial;
    return AlertDialog(
      title: Text(l.parentalRename),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: RenameConsoleDialog.maxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: l.parentalConsoleName,
          helperText: l.parentalConsoleNameHelp,
          helperMaxLines: 2,
          errorText: _error,
          errorMaxLines: 2,
        ),
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) {
          if (changed && !_saving) _save();
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(onPressed: changed && !_saving ? _save : null, child: Text(l.parentalSave)),
      ],
    );
  }
}

/// The new PIN, typed twice. Exactly four digits: the console's entry field
/// has four places, so a longer PIN could never be typed there. The fields
/// go with the dialog; nothing of them is kept.
class NewPinDialog extends StatefulWidget {
  const NewPinDialog({super.key});

  @override
  State<NewPinDialog> createState() => _NewPinDialogState();
}

/// Whether [pin] is one the console can be given and typed on.
bool validNewPin(String pin) => RegExp(r'^[0-9]{4}$').hasMatch(pin);

class _NewPinDialogState extends State<NewPinDialog> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _second = TextEditingController();

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Widget _pinField(TextEditingController c, String label, String? Function(String?) validator, {String? help}) =>
      TextFormField(
        controller: c,
        autofocus: c == _first,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        decoration: InputDecoration(labelText: label, helperText: help, counterText: ''),
        validator: validator,
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.parentalChangePin),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pinField(
              _first,
              l.parentalNewPin,
              (v) => validNewPin(v ?? '') ? null : l.parentalPinInvalid,
              help: l.parentalPinFourDigits,
            ),
            _pinField(_second, l.parentalNewPinAgain, (v) => v == _first.text ? null : l.parentalPinMismatch),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) Navigator.pop(context, _first.text);
          },
          child: Text(l.parentalSave),
        ),
      ],
    );
  }
}

/// A player's picture from the console, or their initial while there is none.
class _PlayerImage extends StatelessWidget {
  const _PlayerImage({required this.name, required this.image});
  final String name;
  final Future<Uint8List?> image;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: image,
    builder: (context, snap) => snap.data == null
        ? Avatar(name: name)
        : ClipOval(
            child: Image.memory(
              snap.data!,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Avatar(name: name),
            ),
          ),
  );
}

/// A value from the setting document by its path; null wherever it is not
/// the shape the console uses.
Object? settingAt(Object? m, List<String> path) {
  Object? v = m;
  for (final k in path) {
    if (v is! Map) return null;
    v = v[k];
  }
  return v;
}

/// Rating organisations by their own names, which are not translated.
const ratingSystems = {
  'CERO': 'CERO',
  'GRAC_GCRB': 'GRAC/GCRB',
  'GSRMR': 'GSRMR',
  'ESRB': 'ESRB',
  'CLASS_IND': 'ClassInd',
  'USK': 'USK',
  'PEGI': 'PEGI',
  'PEGI_PORTUGAL': 'PEGI Portugal',
  'PEGI_BBFC': 'PEGI BBFC',
  'RUSSIAN': 'Russia',
  'ACB': 'ACB',
  'OFLC': 'OFLC',
  'IARC_GENERIC': 'IARC',
  'GMEDIA': 'GMEDIA',
};

/// The setting as (label, value) rows, in the website's order. The level's
/// own presets are the console's, so only CUSTOM lists its parts. A value
/// this app has no word for is shown as the console sent it.
List<(String, String)> _restrictions(BuildContext context, Map<String, dynamic> s) {
  final l = context.l10n;
  String restriction(Object? v) => switch (v) {
    'RESTRICTED' => l.parentalRestricted,
    'UNRESTRICTED' => l.parentalAllowed,
    _ => l.parentalNotSet,
  };
  String clock(Object? v) => v is Map && v['hour'] is num && v['minute'] is num
      ? TimeOfDay(hour: (v['hour'] as num).toInt(), minute: (v['minute'] as num).toInt()).format(context)
      : '';
  String limit(Object? day) {
    final minutes = settingAt(day, ['timeToPlayInOneDay', 'limitTime']);
    return settingAt(day, ['timeToPlayInOneDay', 'enabled']) == true && minutes is num
        ? l.parentalMinutesADay(minutes.toInt())
        : l.parentalNoLimit;
  }

  String? bedtime(Object? day) {
    final b = settingAt(day, ['bedtime']);
    if (b is! Map || b['enabled'] != true) return null;
    final start = clock(b['startingTime']), end = clock(b['endingTime']);
    if (start.isEmpty) return end.isEmpty ? null : end;
    return end.isEmpty ? l.parentalBedtimeFrom(start) : l.parentalBedtimeRange(start, end);
  }

  final rows = <(String, String)>[];
  final level = s['functionalRestrictionLevel'];
  if (level is String) {
    rows.add((
      l.parentalLevel,
      switch (level) {
        'NONE' => l.parentalLevelNone,
        'CHILDREN' => l.parentalLevelChildren,
        'YOUNG_TEENS' => l.parentalLevelYoungTeens,
        'OLDER_TEENS' => l.parentalLevelOlderTeens,
        'CUSTOM' => l.parentalLevelCustom,
        _ => level,
      },
    ));
  }
  if (level == 'CUSTOM') {
    final age = settingAt(s, ['customSettings', 'ageRestriction', 'ratingAge']);
    rows.add((
      l.parentalAgeLimit,
      settingAt(s, ['customSettings', 'ageRestriction', 'restriction']) == 'RESTRICTED' && age is num
          ? l.parentalAgeUpTo(age.toInt())
          : l.parentalNoAgeLimit,
    ));
    final org = settingAt(s, ['customSettings', 'ratingOrganization']);
    if (org is String) rows.add((l.parentalRatingSystem, ratingSystems[org] ?? org));
    final apps = settingAt(s, ['customSettings', 'ugcRestriction', 'applications']);
    final ugc = restriction(settingAt(s, ['customSettings', 'ugcRestriction', 'restriction']));
    rows.add((
      l.parentalCommunication,
      apps is Map && apps.isNotEmpty ? '$ugc\n${l.parentalGamesSetIndividually(apps.length)}' : ugc,
    ));
    rows.add((l.parentalSocialPosting, restriction(settingAt(s, ['customSettings', 'snsPostRestriction']))));
    rows.add((l.parentalVr, restriction(settingAt(s, ['customSettings', 'vrRestriction']))));
  }
  final timer = s['playTimerRegulations'];
  if (timer is Map<String, dynamic>) {
    if (timer['timerMode'] == 'EACH_DAY_OF_THE_WEEK') {
      final days = timer['eachDayOfTheWeekRegulations'];
      if (days is Map) {
        // In the order the console sent them, each under the locale's name.
        for (final MapEntry(:key, :value) in days.entries) {
          final bed = bedtime(value);
          rows.add((weekdayName(l, '$key'), bed == null ? limit(value) : '${limit(value)}\n${l.parentalBedtime}: $bed'));
        }
      }
    } else {
      final day = timer['dailyRegulations'];
      rows.add((l.parentalPlayTime, limit(day)));
      if (bedtime(day) case final bed?) rows.add((l.parentalBedtime, bed));
    }
    final mode = switch (timer['restrictionMode']) {
      'ALARM' => l.parentalAlarmOnly,
      'FORCED_TERMINATION' => l.parentalSuspendGame,
      _ => null,
    };
    if (mode != null) rows.add((l.parentalWhenTimeIsUp, mode));
  }
  return rows;
}

/// The keys a week's rules are filed under, Monday first. The console's
/// event uploads name days so (study §4); no console has yet sent a week of
/// rules to confirm the same keys there.
const weekdayKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

/// "monday" as the locale names it; a key it does not know, as sent.
String weekdayName(AppLocalizations l, String key) {
  final i = weekdayKeys.indexOf(key.toLowerCase());
  // 2024-01-01 was a Monday.
  return i < 0 ? key : DateFormat.EEEE(l.localeName).format(DateTime(2024, 1, 1 + i));
}

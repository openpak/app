import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// One paired console: what it is set to, who plays on it, and its PIN.
/// Read-only; the setting is shown as the console is served it, in the order
/// the website's page uses.
class ParentalConsolePage extends StatefulWidget {
  const ParentalConsolePage({super.key, required this.api, required this.device});
  final OpenPakApi api;
  final ParentalDevice device;

  @override
  State<ParentalConsolePage> createState() => _ParentalConsolePageState();
}

class _ParentalConsolePageState extends State<ParentalConsolePage> {
  late ParentalDevice _device = widget.device;
  final _images = <String, Future<Uint8List?>>{};
  late final AppLifecycleListener _life;

  /// The PIN lives here and on screen, nowhere else: not on disk, not in a
  /// log. It goes whenever the app stops being in front and with the screen.
  String? _pin;
  bool _noPin = false;
  bool _fetchingPin = false;

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
      setState(() => _device = d);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    final d = _device;
    final name = d.nickname.isEmpty ? l.parentalConsole : d.nickname;
    final restrictions = _restrictions(context, d.setting);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(name)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: _refresh,
        child: ListView(
          padding: pagePadding(context),
          children: [
            Panel(
              child: ListTile(
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
            ),
            if (restrictions.isNotEmpty) ...[
              const SizedBox(height: 16),
              SectionLabel(l.parentalRestrictions),
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
            Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_noPin)
                      Text(l.parentalPinNone)
                    else
                      Text(
                        // Four dots whatever the length, so the mask does not
                        // tell anyone how long the PIN is.
                        _pin ?? '••••',
                        style: const TextStyle(fontSize: 30, fontFamily: 'monospace', letterSpacing: 6),
                      ),
                    const SizedBox(height: 8),
                    Text(l.parentalPinHelp, style: TextStyle(color: t.muted, fontSize: 13)),
                    // The PIN's actions sit in a row of their own, so changing
                    // it (a later phase) is one more button, not a new layout.
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _fetchingPin ? null : (_pin == null ? _showPin : _hidePin),
                            icon: Icon(_pin == null ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            label: Text(_pin == null ? l.parentalShowPin : l.parentalHidePin),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
          ],
        ),
      ),
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
Object? _at(Object? m, List<String> path) {
  Object? v = m;
  for (final k in path) {
    if (v is! Map) return null;
    v = v[k];
  }
  return v;
}

/// Rating organisations by their own names, which are not translated.
const _ratingSystems = {
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
    final minutes = _at(day, ['timeToPlayInOneDay', 'limitTime']);
    return _at(day, ['timeToPlayInOneDay', 'enabled']) == true && minutes is num
        ? l.parentalMinutesADay(minutes.toInt())
        : l.parentalNoLimit;
  }

  String? bedtime(Object? day) {
    final b = _at(day, ['bedtime']);
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
    final age = _at(s, ['customSettings', 'ageRestriction', 'ratingAge']);
    rows.add((
      l.parentalAgeLimit,
      _at(s, ['customSettings', 'ageRestriction', 'restriction']) == 'RESTRICTED' && age is num
          ? l.parentalAgeUpTo(age.toInt())
          : l.parentalNoAgeLimit,
    ));
    final org = _at(s, ['customSettings', 'ratingOrganization']);
    if (org is String) rows.add((l.parentalRatingSystem, _ratingSystems[org] ?? org));
    final apps = _at(s, ['customSettings', 'ugcRestriction', 'applications']);
    final ugc = restriction(_at(s, ['customSettings', 'ugcRestriction', 'restriction']));
    rows.add((
      l.parentalCommunication,
      apps is Map && apps.isNotEmpty ? '$ugc\n${l.parentalGamesSetIndividually(apps.length)}' : ugc,
    ));
    rows.add((l.parentalSocialPosting, restriction(_at(s, ['customSettings', 'snsPostRestriction']))));
    rows.add((l.parentalVr, restriction(_at(s, ['customSettings', 'vrRestriction']))));
  }
  final timer = s['playTimerRegulations'];
  if (timer is Map<String, dynamic>) {
    if (timer['timerMode'] == 'EACH_DAY_OF_THE_WEEK') {
      final days = timer['eachDayOfTheWeekRegulations'];
      if (days is Map) {
        // In the order the console sent them, each under the locale's name.
        for (final MapEntry(:key, :value) in days.entries) {
          final bed = bedtime(value);
          rows.add((_weekday(l, '$key'), bed == null ? limit(value) : '${limit(value)}\n${l.parentalBedtime}: $bed'));
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

const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

/// "monday" as the locale names it; a key it does not know, as sent.
String _weekday(AppLocalizations l, String key) {
  final i = _weekdays.indexOf(key.toLowerCase());
  // 2024-01-01 was a Monday.
  return i < 0 ? key : DateFormat.EEEE(l.localeName).format(DateTime(2024, 1, 1 + i));
}

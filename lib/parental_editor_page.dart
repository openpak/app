import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'l10n.dart';
import 'parental_console_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// The console's own bounds for the numbers the form edits: each is what its
/// handler in the console's parse table enforces (study §5b; nx-baas
/// pctlSettingSchema). A value past one ends the console's parse.
const parentalMax = {'ratingAge': 255, 'limitTime': 360, 'hour': 23, 'minute': 59};

/// [text] as a whole number from 0 to [max], or null when it is not one.
int? parentalNumber(String text, int max) {
  final n = int.tryParse(text.trim());
  return n != null && n >= 0 && n <= max ? n : null;
}

/// The document to send: the one served, with each dotted path in [changes]
/// set. Everything the form does not show — dozens of per-title entries, a
/// key a newer console added — goes back exactly as it came.
///
/// A timer touched for the first time is given its mode and what happens when
/// time is up (the values the form shows for absent ones), and a day it
/// touches both of its switches, so the console never reads half a timer.
Map<String, dynamic> mergeSetting(Map<String, dynamic> served, Map<String, Object?> changes) {
  // A copy through JSON: every level is new, so the served map is never
  // written to, and the result is exactly what jsonEncode will send.
  final doc = jsonDecode(jsonEncode(served)) as Map<String, dynamic>;
  final days = <String>{};
  for (final MapEntry(:key, :value) in changes.entries) {
    _put(doc, key.split('.'), value);
    final p = key.split('.');
    if (p.length > 2 && p[1] == 'dailyRegulations') days.add(p.take(2).join('.'));
    if (p.length > 3 && p[1] == 'eachDayOfTheWeekRegulations') days.add(p.take(3).join('.'));
  }
  if (changes.keys.any((k) => k.startsWith('playTimerRegulations.'))) {
    final timer = doc['playTimerRegulations'] as Map<String, dynamic>;
    timer.putIfAbsent('timerMode', () => 'DAILY');
    timer.putIfAbsent('restrictionMode', () => 'ALARM');
  }
  for (final day in days) {
    for (final part in ['timeToPlayInOneDay', 'bedtime']) {
      if (settingAt(doc, [...day.split('.'), part, 'enabled']) == null) _put(doc, [...day.split('.'), part, 'enabled'], false);
    }
  }
  return doc;
}

void _put(Map<String, dynamic> m, List<String> path, Object? v) {
  var at = m;
  for (final k in path.take(path.length - 1)) {
    final next = at[k];
    at = at[k] = next is Map<String, dynamic> ? next : <String, dynamic>{};
  }
  at[path.last] = v;
}

/// Which of the form's [fields] a refused [path] belongs to: the field
/// itself, one it lies under (the hour of a bedtime), or the first one under
/// it (a whole section refused). Null when the form does not show it.
String? parentalFieldFor(String path, Iterable<String> fields) {
  for (final f in fields) {
    if (f == path || path.startsWith('$f.') || f.startsWith('$path.')) return f;
  }
  return null;
}

/// The restrictions of one console, as a form. Only what the parse table
/// types and the console's own settings offer; per-title exceptions and
/// always-allowed titles are kept as served. Pops true once saved, false when
/// the console turned out to be gone.
class ParentalEditorPage extends StatefulWidget {
  const ParentalEditorPage({super.key, required this.api, required this.device});
  final OpenPakApi api;
  final ParentalDevice device;

  @override
  State<ParentalEditorPage> createState() => _ParentalEditorPageState();
}

class _ParentalEditorPageState extends State<ParentalEditorPage> {
  final _form = GlobalKey<FormState>();
  final _changes = <String, Object?>{};
  final _keys = <String, GlobalKey>{};
  bool _saving = false;

  /// The field the server refused, and a refused path no field shows.
  String? _refused;
  String? _refusedElsewhere;

  /// The paths of the fields on screen, in order; rebuilt with them.
  final _shown = <String>[];

  Object? _value(String path) =>
      _changes.containsKey(path) ? _changes[path] : settingAt(widget.device.setting, path.split('.'));

  void _set(String path, Object? v) => setState(() {
    _changes[path] = v;
    if (_refused == path) _refused = null;
  });

  Future<void> _save() async {
    final l = context.l10n;
    // A number left half-typed in a field since hidden (a limit switched off)
    // goes back to what was served rather than blocking the save unseen.
    _changes.removeWhere((k, v) => v is String && parentalMax.containsKey(k.split('.').last) && !_shown.contains(k));
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _refused = _refusedElsewhere = null;
    });
    try {
      await widget.api.parentalSaveSetting(widget.device.moonId, mergeSetting(widget.device.setting, _changes));
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        Navigator.pop(context, false);
      } else if (e.statusCode == 400 && e.path != null) {
        final field = parentalFieldFor(e.path!, _shown);
        setState(() {
          _refused = field;
          _refusedElsewhere = field == null ? e.path : null;
        });
        final at = field == null ? null : _keys[field]?.currentContext;
        if (at != null && at.mounted) Scrollable.ensureVisible(at, alignment: 0.3);
      } else {
        showToast(context, apiErrorText(l, e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// One field on screen: keyed by its path, so a refusal can find it, with
  /// the refusal under it.
  Widget _field(String path, Widget child) {
    _shown.add(path);
    final t = tokensOf(context);
    return KeyedSubtree(
      key: ValueKey('parental:$path'),
      child: Column(
        key: _keys.putIfAbsent(path, GlobalKey.new),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          if (_refused == path)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(context.l10n.parentalRefusedField, style: TextStyle(color: t.bad, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  /// A choice among the console's enum values; [shown] stands for an absent
  /// value the console treats as that one. A value outside [options] (an
  /// UNDEFINED, a key a newer console sent) reads as "Not set" and is kept.
  Widget _choice(String path, String label, Map<String, String> options, {String? shown}) {
    final v = _value(path);
    final current = options.containsKey(v) ? v as String : shown;
    return _field(
      path,
      ListTile(
        title: Text(label),
        trailing: DropdownButton<String>(
          value: current,
          hint: Text(context.l10n.parentalNotSet),
          underline: const SizedBox.shrink(),
          items: [
            for (final MapEntry(:key, :value) in options.entries) DropdownMenuItem(value: key, child: Text(value)),
          ],
          onChanged: (v) => _set(path, v),
        ),
      ),
    );
  }

  Widget _switch(String path, String label, {required String on, required String off}) => _field(
    path,
    SwitchListTile(
      title: Text(label),
      value: _value(path) == on,
      onChanged: (v) => _set(path, v ? on : off),
    ),
  );

  Widget _toggle(String path, String label, {VoidCallback? whenOn}) => _field(
    path,
    SwitchListTile(
      title: Text(label),
      value: _value(path) == true,
      onChanged: (v) {
        _set(path, v);
        if (v) whenOn?.call();
      },
    ),
  );

  Widget _number(String path, String label, int max) {
    final l = context.l10n;
    final v = _value(path);
    return _field(
      path,
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: TextFormField(
          initialValue: v is num ? '${v.toInt()}' : (v is String ? v : ''),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (s) => parentalNumber(s ?? '', max) == null ? l.parentalNumberRange(max) : null,
          // Kept as typed until it is a number, so the check above sees it.
          onChanged: (s) => _set(path, parentalNumber(s, max) ?? s),
        ),
      ),
    );
  }

  /// A time the console reads as {hour, minute}. Chosen on a clock, so it is
  /// always in the console's bounds.
  Widget _time(String path, String label) {
    final hour = _value('$path.hour'), minute = _value('$path.minute');
    final time = hour is num && minute is num ? TimeOfDay(hour: hour.toInt(), minute: minute.toInt()) : null;
    return _field(
      path,
      ListTile(
        title: Text(label),
        trailing: Text(time?.format(context) ?? '--:--'),
        onTap: () async {
          final picked = await showTimePicker(context: context, initialTime: time ?? _bedtimeDefault);
          if (picked == null) return;
          _set('$path.hour', picked.hour);
          _set('$path.minute', picked.minute);
        },
      ),
    );
  }

  static const _bedtimeDefault = TimeOfDay(hour: 21, minute: 0);

  /// One day's limit and bedtime, under [day] (the daily rules, or a weekday's).
  List<Widget> _day(String day) {
    final l = context.l10n;
    final limit = '$day.timeToPlayInOneDay', bed = '$day.bedtime';
    return [
      _toggle('$limit.enabled', l.parentalLimitPlayTime),
      if (_value('$limit.enabled') == true) _number('$limit.limitTime', l.parentalMinutesField, parentalMax['limitTime']!),
      _toggle(
        '$bed.enabled',
        l.parentalBedtimeAlarm,
        // A bedtime switched on is never without a time.
        whenOn: () {
          if (_value('$bed.startingTime.hour') is! num || _value('$bed.startingTime.minute') is! num) {
            _set('$bed.startingTime.hour', _bedtimeDefault.hour);
            _set('$bed.startingTime.minute', _bedtimeDefault.minute);
          }
        },
      ),
      if (_value('$bed.enabled') == true) _time('$bed.startingTime', l.parentalBedtime),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    _shown.clear();
    final restriction = {'UNRESTRICTED': l.parentalAllowed, 'RESTRICTED': l.parentalRestricted};
    final custom = _value('functionalRestrictionLevel') == 'CUSTOM';
    final apps = settingAt(widget.device.setting, ['customSettings', 'ugcRestriction', 'applications']);
    final eachDay = _value('playTimerRegulations.timerMode') == 'EACH_DAY_OF_THE_WEEK';

    Widget panel(List<Widget> children) => Panel(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(height: 1), children[i]],
        ],
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.parentalChangeRestrictions)),
      // A Builder, so the padding is read below the Scaffold: with
      // extendBodyBehindAppBar the Scaffold's MediaQuery counts the app bar in
      // its top padding, and this page's own context, above it, only the
      // status bar. Read from there, the first panel sat under the bar.
      body: Builder(
        // A column, not a lazy list: a field scrolled out of view must still
        // be checked on save, and a refusal must still find it.
        builder: (context) => Form(
          key: _form,
          child: SingleChildScrollView(
            padding: pagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              if (_refusedElsewhere != null) ...[Notice(l.parentalRefused(_refusedElsewhere!)), const SizedBox(height: 16)],
              SectionLabel(l.parentalRestrictions),
              panel([
                _choice('functionalRestrictionLevel', l.parentalLevel, {
                  'NONE': l.parentalLevelNone,
                  'CHILDREN': l.parentalLevelChildren,
                  'YOUNG_TEENS': l.parentalLevelYoungTeens,
                  'OLDER_TEENS': l.parentalLevelOlderTeens,
                  'CUSTOM': l.parentalLevelCustom,
                }),
                // The other levels are the console's own presets; only Custom
                // has parts to set.
                if (custom) ...[
                  _switch(
                    'customSettings.ageRestriction.restriction',
                    l.parentalLimitByAge,
                    on: 'RESTRICTED',
                    off: 'UNRESTRICTED',
                  ),
                  if (_value('customSettings.ageRestriction.restriction') == 'RESTRICTED')
                    _number('customSettings.ageRestriction.ratingAge', l.parentalUpToAgeField, parentalMax['ratingAge']!),
                  _choice('customSettings.ratingOrganization', l.parentalRatingSystem, ratingSystems),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _choice('customSettings.ugcRestriction.restriction', l.parentalCommunication, restriction),
                      if (apps is Map && apps.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            l.parentalGamesSetIndividually(apps.length),
                            style: TextStyle(color: t.muted, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                  _choice('customSettings.snsPostRestriction', l.parentalSocialPosting, restriction),
                  _choice('customSettings.vrRestriction', l.parentalVr, restriction),
                ],
              ]),
              const SizedBox(height: 16),
              SectionLabel(l.parentalPlayTime),
              panel([
                _choice('playTimerRegulations.timerMode', l.parentalTimer, {
                  'DAILY': l.parentalTimerDaily,
                  'EACH_DAY_OF_THE_WEEK': l.parentalTimerEachDay,
                }, shown: 'DAILY'),
                if (!eachDay) ..._day('playTimerRegulations.dailyRegulations'),
                _choice('playTimerRegulations.restrictionMode', l.parentalWhenTimeIsUp, {
                  'ALARM': l.parentalAlarmOnly,
                  'FORCED_TERMINATION': l.parentalSuspendGame,
                }, shown: 'ALARM'),
              ]),
              if (eachDay)
                for (final day in weekdayKeys) ...[
                  const SizedBox(height: 16),
                  SectionLabel(weekdayName(l, day)),
                  panel(_day('playTimerRegulations.eachDayOfTheWeekRegulations.$day')),
                ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving || _changes.isEmpty ? null : _save,
                child: Text(l.parentalSave),
              ),
              const SizedBox(height: 16),
              Text(l.parentalSyncHelp, style: TextStyle(color: t.muted, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

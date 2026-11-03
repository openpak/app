import 'package:flutter/material.dart';

import 'api.dart';
import 'companion_widgets.dart';
import 'l10n.dart';
import 'theme.dart';
import 'titles_page.dart' show newsDate;
import 'widgets.dart';

/// A play time as "3 h 20 min" or "45 min".
String playDuration(AppLocalizations l, int seconds) {
  final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60;
  return h == 0 ? l.activityM(m) : l.activityHm(h, m);
}

String _network(String ns) => switch (ns) {
  'wfc' => 'Wii / DS',
  'xbox' => 'Xbox',
  'x360' => 'Xbox 360',
  'np' => 'PlayStation 3',
  'switch' => 'Nintendo Switch',
  '3ds' => 'Nintendo 3DS',
  'wiiu' => 'Wii U',
  '' => '',
  _ => ns[0].toUpperCase() + ns.substring(1),
};

/// A play history laid out as the website's shared card: three figures, then the
/// games newest first, each with a bar for its share of the most played one.
CompanionCard activityCard(AppLocalizations l, PlayActivity a) {
  final top = a.titles.fold<int>(1, (m, t) => t.seconds > m ? t.seconds : m);
  return CompanionCard(
    linked: true,
    stats: [
      CardStat(
        key: 'activity.total',
        value: playDuration(l, a.totalSeconds),
        n: a.totalSeconds,
      ),
      CardStat(
        key: 'activity.games',
        value: '${a.titles.length}',
        n: a.titles.length,
      ),
      CardStat(key: 'activity.sessions', value: '${a.sessions}', n: a.sessions),
    ],
    rows: [
      for (final t in a.newestFirst)
        CardRow(
          title: t.title.isEmpty ? l.activityUnknown : t.title,
          sub: [
            _network(t.network),
            l.activitySessionsN(t.sessions),
            if (t.last != null) '${l.activityLast} ${newsDate(l, t.last!)}',
          ].where((s) => s.isNotEmpty).join(' · '),
          value: playDuration(l, t.seconds),
          percent: t.seconds * 100 ~/ top,
        ),
    ],
  );
}

/// What the signed-in account has played, on every network, as /account/activity.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  late Future<PlayActivity> _data = widget.api.playActivity();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = tokensOf(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.activityTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: () async =>
            setState(() => _data = widget.api.playActivity()),
        child: FutureBuilder<PlayActivity>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final pad = pagePadding(context, top: 12);
            if (snap.hasError) return LoadFailure(snap.error);
            final a = snap.data!;
            return ListView(
              padding: pad,
              children: [
                Text(
                  l.activitySub,
                  style: TextStyle(color: t.ink2, height: 1.4),
                ),
                const SizedBox(height: 14),
                if (a.titles.isEmpty)
                  EmptyNote(l.activityEmpty)
                else
                  CardView(card: activityCard(l, a)),
                const SizedBox(height: 12),
                Text(
                  l.activityNote,
                  style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'api.dart';
import 'companion_widgets.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// The PS3 trophies of the signed-in account, as the website's /account/trophies.
class TrophiesPage extends StatefulWidget {
  const TrophiesPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<TrophiesPage> createState() => _TrophiesPageState();
}

class _TrophiesPageState extends State<TrophiesPage> {
  late Future<CompanionCard> _data = widget.api.trophies();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = tokensOf(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.trophiesTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: () async => setState(() => _data = widget.api.trophies()),
        child: FutureBuilder<CompanionCard>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final pad = pagePadding(context, top: 12);
            if (snap.hasError) return LoadFailure(snap.error);
            final c = snap.data!;
            return ListView(
              padding: pad,
              children: [
                Text(
                  l.trophiesSub,
                  style: TextStyle(color: t.ink2, height: 1.4),
                ),
                const SizedBox(height: 14),
                if (!c.linked)
                  EmptyNote(l.trophiesUnlinked)
                else ...[
                  if (c.heading.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        l.trophiesPsn(c.heading),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  CardView(card: c),
                  if (c.rows.isEmpty) EmptyNote(l.trophiesEmpty),
                  const SizedBox(height: 12),
                  Text(
                    l.trophiesNote,
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

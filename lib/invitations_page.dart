import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// What is waiting for you. Reading this consumes nothing, so opening the app
/// never takes an invitation away from the console that has to receive it.
class InvitationsPage extends StatefulWidget {
  const InvitationsPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<InvitationsPage> createState() => _InvitationsPageState();
}

class _InvitationsPageState extends State<InvitationsPage> {
  late Future<List<Invitation>> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _data = widget.api.invitations());

  Future<void> _decline(Invitation inv) async {
    try {
      await widget.api.decline(inv.id);
      if (mounted) showToast(context, 'Declined.');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Invitations')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Invitation>>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return const ScrollableMessage(
                'Could not load. Pull down to try again.',
              );
            }
            final items = snap.data ?? const <Invitation>[];
            if (items.isEmpty) {
              return const ScrollableMessage('Nothing waiting for you.');
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                SectionLabel('Waiting', trailing: '${items.length}'),
                Panel(
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: Avatar(
                            name: items[i].from,
                            dim: items[i].expired,
                          ),
                          title: Text('${items[i].from} invited you'),
                          subtitle: Text(
                            items[i].expired ? 'Expired' : items[i].titleId,
                            style: TextStyle(
                              color: items[i].expired ? t.muted : t.ink2,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: () => _decline(items[i]),
                            child: const Text('Decline'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Accepting happens on your console. This is where you see '
                  'what is waiting and turn things down.',
                  style: TextStyle(color: t.muted, fontSize: 13),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

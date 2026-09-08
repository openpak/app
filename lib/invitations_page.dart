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
              return LoadFailure(snap.error);
            }
            final items = snap.data ?? const <Invitation>[];
            if (items.isEmpty) {
              return const ScrollableMessage('Nothing waiting for you.');
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                SectionLabel('Waiting', trailing: '${items.length}'),
                // Green while it can still be accepted, grey once it cannot:
                // an expired invitation is not a problem, it is just over.
                ...items.map(
                  (inv) => StateRow(
                    name: '${inv.from} invited you',
                    pill: inv.expired ? 'Expired' : inv.titleId,
                    state: inv.expired ? RowState.idle : RowState.ok,
                    leading: Avatar(name: inv.from, dim: inv.expired),
                    trailing: TextButton(
                      onPressed: () => _decline(inv),
                      child: const Text('Decline'),
                    ),
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

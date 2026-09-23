import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
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

  // A block, not an arrow: an arrow would hand setState the Future it assigns.
  void _reload() => setState(() {
    _data = widget.api.invitations();
  });

  Future<void> _decline(Invitation inv) async {
    final l = context.l10n;
    try {
      await widget.api.decline(inv.id);
      if (mounted) showToast(context, l.commonDeclined);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.invitationsTitle)),
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
              return ScrollableMessage(l.invitationsEmpty);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                SectionLabel(l.invitationsWaiting, trailing: '${items.length}'),
                // Green while it can still be accepted, grey once it cannot:
                // an expired invitation is not a problem, it is just over.
                ...items.map(
                  (inv) => StateRow(
                    name: l.invitationsFrom(inv.from),
                    pill: inv.expired ? l.invitationsExpired : inv.titleId,
                    state: inv.expired ? RowState.idle : RowState.ok,
                    leading: Avatar(name: inv.from, dim: inv.expired),
                    trailing: TextButton(
                      onPressed: () => _decline(inv),
                      child: Text(l.commonDecline),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.invitationsNote,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Parental controls, parent side. Nintendo's own parent surface is a separate
/// smartphone app; ours is this screen. The console's half is local to it — the
/// PIN, the limits and the alarm all live on the console — so what happens here
/// is pairing and, later, the settings a paired console syncs.
class ParentalControlsPage extends StatefulWidget {
  const ParentalControlsPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<ParentalControlsPage> createState() => _ParentalControlsPageState();
}

class _ParentalControlsPageState extends State<ParentalControlsPage> {
  late Future<List<ParentalDevice>> _devices;
  bool _pairing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // A block, not an arrow: an arrow would hand setState the Future it assigns.
  void _reload() => setState(() {
    _devices = widget.api.parentalDevices();
  });

  Future<void> _pair() async {
    final l = context.l10n;
    setState(() => _pairing = true);
    try {
      await widget.api.parentalPair();
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
    _reload();
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    showToast(context, context.l10n.parentalCodeCopied);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.parentalTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<ParentalDevice>>(
          future: _devices,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return LoadFailure(snap.error);
            }
            final devices = snap.data ?? const <ParentalDevice>[];
            final waiting = devices.where((d) => d.waiting).toList(growable: false);
            final paired = devices.where((d) => d.paired).toList(growable: false);
            return ListView(
              padding: pagePadding(context),
              children: [
                Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l.parentalHowTo, style: TextStyle(color: t.muted)),
                  ),
                ),
                const SizedBox(height: 16),
                // The code is the whole screen while one is live: it exists to
                // be read off a phone and typed into a console.
                if (waiting.isNotEmpty) ...[
                  SectionLabel(l.parentalCodeLabel),
                  ...waiting.map(
                    (d) => Panel(
                      child: ListTile(
                        title: Text(
                          d.pairingCode,
                          style: const TextStyle(
                            fontSize: 30,
                            fontFamily: 'monospace',
                            letterSpacing: 6,
                          ),
                        ),
                        subtitle: Text(l.parentalCodeValid, style: TextStyle(color: t.muted)),
                        trailing: IconButton(
                          icon: const Icon(Icons.content_copy),
                          tooltip: l.parentalCodeCopy,
                          onPressed: () => _copy(d.pairingCode),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SectionLabel(l.parentalConsoles, trailing: '${paired.length}'),
                if (paired.isEmpty)
                  Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l.parentalNoConsoles, style: TextStyle(color: t.muted)),
                    ),
                  ),
                // A console that has claimed a code. Its restriction settings
                // are not editable yet: the console-facing sync is still being
                // brought up, and an editor that changed nothing would lie.
                ...paired.map(
                  (d) => StateRow(
                    name: l.parentalConsole,
                    pill: d.hasSetting ? l.parentalManaged : l.parentalNoLimits,
                    state: d.hasSetting ? RowState.ok : RowState.idle,
                    leading: const Icon(Icons.videogame_asset_outlined, size: 28),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _pairing ? null : _pair,
                  icon: const Icon(Icons.add),
                  label: Text(l.parentalPairConsole),
                ),
                const SizedBox(height: 16),
                Text(l.parentalOnConsoleNote, style: TextStyle(color: t.muted, fontSize: 13)),
              ],
            );
          },
        ),
      ),
    );
  }
}
